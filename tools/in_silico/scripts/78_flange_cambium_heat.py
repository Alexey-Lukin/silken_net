#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
78 — Does the titanium flange, seated on a shallow facing of the dead bark, shift the extreme temperatures of the
cambium under the ring Ø15–Ø29.8 against bark without it, and where is it worst? (00_07 HW.6 — the price of the
2026-10-03 seat verdict named this path as measured by no instrument.)

QUESTION. Since the 2026-10-03 seat verdict (01_04 §3.1) the flange sits bare on a shallow facing of the DEAD bark.
Ti carries the capsule's temperature down to the bark over the ring, and dead bark is a poor DIURNAL insulator: its
damping depth for a daily wave is √(2κ/ω) ≈ 6 cm against 8–21 mm of it under the flange. So the flange is a heat
source over the cambium exactly when the capsule runs hot.

WHERE IT IS WORST — geometry, before any number. The facing is a PLANE perpendicular to the axis and the phloem
surface a smooth cylinder, so the thinnest bark IN CONTACT with the flange is under the deep edge of the facing,
Ø_flange·sin(angle) deeper than where the plane meets the bark at the shallow edge (01_04 §3.1–3.2). How thin that
is depends on where the plane stops: on the ridges, a furrow deeper than it is an AIR gap under the flange (that path
is not computed here) and the contact is the ridge thickness minus the spread — the thin end below; down to the
furrow bottoms, the contact is thinner by a furrow depth no primary gives — the dead-bark floor below is the
criterion for that facing.

MODEL — 1D transient conduction, Crank–Nicolson, from the flange↔bark interface into the stem: dead bark → phloem →
cambium plane → sapwood; the layer properties and the cambium gate are imported from `58` (one home). Boundary at
the interface: the hourly capsule temperature of `71` (its lumped balance, imported and checked against its own
cache — one home of the sun), i.e. the flange is taken AT the capsule's temperature over 30 ERA5 years, in both of
`71`'s cases (full sun, and diffuse only — under a crown) over its whole α sweep. Inner boundary: ADIABATIC at
SAPWOOD_DEPTH_MM into sapwood.
  • Under-flange dead bark — the canon ridge bracket at DBH 38 (lib.constants, mirror of 01_04 §3.2): the thin end is
    the thin ridge minus the facing spread (the deep edge), the thick end the thick ridge (the shallow edge).
  • Reference: the same column with its surface at AIR temperature — bark without the flange in shade. Sunlit natural
    bark is NOT computed: no bark surface temperature exists in the tree (`71`'s own named ceiling).
  • Two inversions: the α at which the worst cell (full sun, still air) reaches the gate, on `71`'s α grid; and the
    dead-bark thickness left under the flange at which the specified finish reaches it (brentq; resolution ≈ DX_MM).

DIRECTION OF THE BOUND, stated first: 1D (no lateral spreading — the ring is 7.4 mm wide against 8–21 mm of bark),
an adiabatic inner boundary, zero contact resistance flange↔bark and the flange AT the capsule's temperature
(`71`'s lump has an adiabatic base, so it is the hottest node) — each pushes the cambium temperature UP, so the hot
numbers are UPPER bounds and both crossings are conservative: the real α is higher, the real bark floor thinner.

CAN show: the hottest cambium hour under the flange in 30 years and the hours above the gate, per case, finish α,
wind and bark side; the shift against bark without the flange under a crown; the two crossings.
CANNOT show: whether the flange is worse than SUNLIT bark (no bark temperature in the tree); a dose (the gate is an
isotherm — `58`'s ceiling: no Arrhenius parameters for pine cambium); the furrow's air-gap path; frost: in `71` the
capsule tracks air at night (no sky cooling), so the flange and shaded bark meet at night by construction — no frost
verdict is drawn here; the frost half is `79`.

Run:  python tools/in_silico/scripts/78_flange_cambium_heat.py      # ~3–4 min (30 years hourly, 50 columns + a root search)
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.linalg import solve_banded
from scipy.optimize import brentq

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BARK_DEAD_RIDGE_DBH38_MM, CACHE_DIR, INSTALL_ANGLE_DEG, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Cambium temperature under the anchor's titanium flange over thirty years of hourly weather, against bark without it (1D upper bound)."  # its row in the paper SI (72): English, no repo jargon

OUT_DIR = CACHE_DIR / "thermal"
OUT = OUT_DIR / "flange_cambium_heat.json"
FLANGE_CEM = REPO_ROOT / "tools/cad/cem/cathode_flange.json"
SCRIPTS = Path(__file__).resolve().parent

WIND_K = (0.0, 0.1)            # still air (`71`'s bound) and its typical light breeze
CASES = (("sunlit", 1.0), ("shaded", 0.0))   # 71's two cases: beam on the capsule, or diffuse only (under a crown)
SAPWOOD_DEPTH_MM = 100.0       # adiabatic beyond — cuts off the stem's heat sink, an UPPER bound
DX_MM = 0.5
SUBSTEPS_PER_HOUR = 2


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S58 = _load("s58_install", "58_thermal_install_field.py")
GATE_C, UPPER_C = S58.T_CAMBIUM_LIMIT_C, S58.T_CAMBIUM_UPPER_C
ALPHAS, ALPHA_EDGES = S71.ALPHA_SWEEP, S71.ALPHA_EDGES   # 71's sweep and its two quoted ends: the specified ceiling
                                                          # (α ≤ 0.5, 02_01 §5.2) and the retired dark finish


def bark_bracket() -> dict:
    d_flange = json.loads(FLANGE_CEM.read_text(encoding="utf-8"))["flange_diameter_mm"]
    spread = d_flange * math.sin(math.radians(INSTALL_ANGLE_DEG))
    return {"flange_diameter_mm": d_flange, "facing_spread_mm": round(spread, 3),
            "thin_mm": round(BARK_DEAD_RIDGE_DBH38_MM[0] - spread, 3), "thick_mm": BARK_DEAD_RIDGE_DBH38_MM[1]}


def layers(bark_mm: float) -> list:
    """(thickness mm, λ, ρc) outward-in: dead bark → phloem → sapwood, the properties of `58` (one home)."""
    return [(bark_mm, S58.LAMBDA_BARK_DEAD, S58.RHO_BARK_DEAD * S58.CP_BARK_DEAD),
            (S58.T_PHLOEM, S58.LAMBDA_PHLOEM, S58.RHO_PHLOEM * S58.CP_PHLOEM),
            (SAPWOOD_DEPTH_MM, S58.LAMBDA_WOOD, S58.RHO_WOOD * S58.CP_WOOD)]


def column(stack: list, probe_mm: float):
    """Node-centred finite volumes; returns (capacity per area, face conductances, probe node index)."""
    n = round(sum(t for t, _, _ in stack) / DX_MM)
    x = np.arange(n + 1) * DX_MM
    edges = np.cumsum([t for t, _, _ in stack])
    j = np.minimum(np.searchsorted(edges, x + 1e-9), len(stack) - 1)
    lam = np.array([stack[k][1] for k in j])
    rc = np.array([stack[k][2] for k in j])
    dx = DX_MM * 1e-3
    g = 2.0 / (dx / lam[:-1] + dx / lam[1:])          # harmonic face conductance, W/m²K
    cap = rc * dx
    cap[-1] *= 0.5                                     # half cell at the adiabatic end
    return cap, g, math.floor(probe_mm / DX_MM + 1e-9)   # the shallower node — hotter, safe side


def run(surface_c: np.ndarray, stack: list, probe_mm: float, substeps: int = 2) -> np.ndarray:
    """Temperature at `probe_mm` at the end of every hour, for hourly surface series stacked as columns
    (hours × series): every series of one column shares one matrix, so they march together."""
    cap, g, ic = column(stack, probe_mm)
    n = len(g)                                         # unknown nodes 1..n; node 0 is the driven surface
    dt = 3600.0 / substeps
    c = (cap[1:] / dt)[:, None]
    gl = g[:, None]                                    # face to the left of each unknown node
    gr = np.append(g[1:], 0.0)[:, None]                # face to the right (none at the adiabatic end)
    ab = np.zeros((3, n))
    ab[0, 1:] = -0.5 * gr[:-1, 0]
    ab[1, :] = (c + 0.5 * (gl + gr))[:, 0]
    ab[2, :-1] = -0.5 * gl[1:, 0]
    keep = c - 0.5 * (gl + gr)
    t = np.repeat(surface_c[:1], n, axis=0)
    out = np.empty_like(surface_c)
    out[0] = surface_c[0]
    for h in range(1, len(surface_c)):
        step = (surface_c[h] - surface_c[h - 1]) / substeps
        for s in range(substeps):
            fa = surface_c[h - 1] + step * s
            rhs = keep * t
            rhs[1:] += 0.5 * gl[1:] * t[:-1]
            rhs[:-1] += 0.5 * gr[:-1] * t[1:]
            rhs[0] += 0.5 * gl[0, 0] * (2.0 * fa + step)
            t = solve_banded((1, 1), ab, rhs, check_finite=False)
        out[h] = t[ic - 1]
    return out


def verify_scheme() -> float:
    """The scheme against the closed form: a 24 h sinusoid on a homogeneous dead-bark half-space damps as
    exp(−x/d), d = √(2κ/ω). Returns the worst relative amplitude error over three depths (fundamental fitted
    over the last five periods; the hourly linear interpolation of the forcing alone costs ≈ 0.6 %)."""
    lam, rc = S58.LAMBDA_BARK_DEAD, S58.RHO_BARK_DEAD * S58.CP_BARK_DEAD
    d = math.sqrt(2.0 * lam / rc / (2.0 * math.pi / 86400.0))
    hrs = np.arange(24 * 20)
    tail = hrs[-24 * 5:]
    err = 0.0
    for depth in (5.0, 10.0, 20.0):
        out = run(10.0 * np.sin(2.0 * np.pi * hrs / 24.0)[:, None], [(300.0, lam, rc)], depth, SUBSTEPS_PER_HOUR)
        y = out[-24 * 5:, 0]
        amp = 2.0 / len(tail) * math.hypot(float(np.sum(y * np.sin(2 * np.pi * tail / 24))),
                                           float(np.sum(y * np.cos(2 * np.pi * tail / 24))))
        want = 10.0 * math.exp(-math.floor(depth / DX_MM + 1e-9) * DX_MM * 1e-3 / d)
        err = max(err, abs(amp - want) / want)
    return err


def summarise(series: np.ndarray, times: np.ndarray) -> dict:
    i = int(np.argmax(series))
    return {"cambium_max_C": round(float(series[i]), 2), "at": str(times[i]),
            "hours_above_gate": int(np.count_nonzero(series > GATE_C)),
            "hours_above_upper": int(np.count_nonzero(series > UPPER_C))}


def crossing(xs, ys, level):
    """Where a rising piecewise-linear y(x) first reaches `level`: xs[0] if already there, None if never in the sweep."""
    if ys[0] >= level:
        return xs[0]
    for i in range(1, len(xs)):
        if ys[i] >= level:
            return round(xs[i - 1] + (xs[i] - xs[i - 1]) * (level - ys[i - 1]) / (ys[i] - ys[i - 1]), 3)
    return None


def bark_floor(t_cap: np.ndarray, thin_mm: float):
    """The dead-bark thickness left under the flange below which the cambium reaches the gate (the 30-year maximum
    falls with thickness); None if not reached even with no dead bark left, `thin_mm` if already at the thin end."""
    def excess(b):
        return float(run(t_cap[:, None], layers(b), b + S58.T_PHLOEM, SUBSTEPS_PER_HOUR).max()) - GATE_C
    if excess(0.0) <= 0.0:
        return None
    if excess(thin_mm) >= 0.0:
        return thin_mm
    return round(brentq(excess, 0.0, thin_mm, xtol=0.05), 1)


def main() -> int:
    banner("HW.6 — cambium under the titanium flange vs bark without it, 30 ERA5 years (1D upper bound)")
    h = S71.load_hours()
    geo = S71.geometry()
    a_proj, a_exp, d_m = geo["a_proj_max_mm2"] * 1e-6, geo["a_exp_mm2"] * 1e-6, geo["dome_diameter_mm"] * 1e-3
    cached = json.loads((OUT_DIR / "capsule_envelope.json").read_text(encoding="utf-8"))["hot_bound"]
    bark = bark_bracket()
    times = h["time"]
    scheme_err = verify_scheme()
    if scheme_err > 0.01:
        raise SystemExit(f"scheme check failed: {scheme_err:.2%} off the closed-form diurnal damping")
    print(f"  scheme check: homogeneous half-space, 24 h wave — amplitude within {scheme_err:.2%} of exp(−x/d)")
    print(f"  under-flange dead bark: {bark['thin_mm']:.2f}–{bark['thick_mm']:.1f} mm (ridges {BARK_DEAD_RIDGE_DBH38_MM} "
          f"minus the {bark['facing_spread_mm']:.2f} mm facing spread at {INSTALL_ANGLE_DEG:.0f}°) · gate {GATE_C:.0f} °C")

    # The flange-driven series: 71's capsule temperature, reproduced from its own code and checked against its cache.
    keys, series = [], []
    for case, beam in CASES:
        for alpha in ALPHAS:
            q = alpha * (beam * h["dni"] * a_proj + S71.SKY_VIEW * h["dif"] * a_exp)
            for k in WIND_K:
                t_cap = S71.solve_t_cap(h["t_air"], q, a_exp, d_m, k * h["u10"])
                want = cached[case][f"{alpha:.2f}"][f"{k:.1f}"]["t_cap_max_c"]
                if abs(round(float(t_cap.max()), 1) - want) > 0.05:
                    raise SystemExit(f"71 does not reproduce its own cache: {t_cap.max():.2f} vs {want} ({case}, α {alpha}, k {k})")
                keys.append((case, alpha, k))
                series.append(t_cap)
    stack = np.column_stack([*series, h["t_air"]])     # last column: bark without the flange, surface at air

    runs, reference = [], {}
    for side, b in (("thin", bark["thin_mm"]), ("thick", bark["thick_mm"])):
        cam = run(stack, layers(b), b + S58.T_PHLOEM, SUBSTEPS_PER_HOUR)
        reference[side] = {"bark_mm": b, **summarise(cam[:, -1], times)}
        for col, (case, alpha, k) in enumerate(keys):
            runs.append({"case": case, "alpha": alpha, "wind_k": k, "bark_side": side, "bark_mm": b,
                         "flange_max_C": round(float(series[col].max()), 1), **summarise(cam[:, col], times)})

    def cell(case, alpha, k, side):
        return next(r for r in runs if (r["case"], r["alpha"], r["wind_k"], r["bark_side"]) == (case, alpha, k, side))

    print("  cambium max, °C — the hottest hour of 30 years; α →  " + "  ".join(f"{a:.2f}" for a in ALPHAS))
    for case, _ in CASES:
        for k in WIND_K:
            for side in reference:
                print(f"    {case:<6s} k {k:.1f} · {side:<5s} bark {cell(case, ALPHAS[0], k, side)['bark_mm']:5.2f} mm   "
                      + "  ".join(f"{cell(case, a, k, side)['cambium_max_C']:4.1f}" for a in ALPHAS))
    for side, ref in reference.items():
        print(f"    no flange, surface at air · {side:<5s} {ref['cambium_max_C']:.1f}")

    lo, hi = ALPHA_EDGES
    still = WIND_K[0]
    worst = {f"{case}_{a:.2f}": max((r for r in runs if r["case"] == case and r["alpha"] == a), key=lambda r: r["cambium_max_C"])
             for case, _ in CASES for a in ALPHAS}
    shift = {f"{a:.2f}": round(max(cell("shaded", a, k, side)["cambium_max_C"] - reference[side]["cambium_max_C"]
                                   for k in WIND_K for side in reference), 2) for a in ALPHAS}
    a_star = {side: crossing(ALPHAS, [cell("sunlit", a, still, side)["cambium_max_C"] for a in ALPHAS], GATE_C)
              for side in reference}
    floor_mm = bark_floor(series[keys.index(("sunlit", lo, still))], bark["thin_mm"])
    ref_max = max(v["cambium_max_C"] for v in reference.values())
    spec = worst[f"sunlit_{lo:.2f}"]

    def past(a):
        return "nowhere in the sweep" if a is None else f"past α ≈ {a:.2f}"
    first = (f"no hour of 30 years puts the cambium under the flange above {GATE_C:.0f} °C, even in full sun and still "
             f"air (hottest {spec['cambium_max_C']:.1f} °C)" if spec["hours_above_gate"] == 0 else
             f"{spec['hours_above_gate']} hours of 30 years put the cambium under the flange above {GATE_C:.0f} °C in "
             f"full sun (hottest {spec['cambium_max_C']:.1f} °C)")
    floor_txt = ("not even with no dead bark left" if floor_mm is None
                 else f"with less than ≈ {floor_mm:.1f} mm of dead bark left under the flange")
    text = (f"With the specified finish (α {lo:.2f}) {first}. The gate is reached {past(a_star['thin'])} on the "
            f"bracket's thinnest contact ({bark['thin_mm']:.1f} mm of dead bark; {past(a_star['thick'])} on "
            f"{bark['thick_mm']:.1f} mm), or at α {lo:.2f} {floor_txt}. Under a crown the flange raises the hottest "
            f"cambium hour by up to +{shift[f'{lo:.2f}']:.1f} K at α {lo:.2f} (+{shift[f'{hi:.2f}']:.1f} K at α "
            f"{hi:.2f}) over bark without it ({ref_max:.1f} °C). In full sun there is no reference: sunlit bark has no "
            f"temperature anywhere in the tree. Every number is a 1D UPPER bound, so both crossings are conservative.")
    print(f"\n  → {text}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "question": "does the Ti flange on the faced dead bark shift the extreme cambium temperatures under the "
                    "Ø15–Ø29.8 ring against bark without it, and where is it worst?",
        "method": "1D Crank–Nicolson conduction (dead bark → phloem → sapwood, properties from 58) driven at the "
                  "flange↔bark interface by 71's hourly capsule temperature over 30 ERA5 years; adiabatic inner end",
        "inputs": {"alphas": list(ALPHAS), "alpha_edges": list(ALPHA_EDGES), "wind_k": list(WIND_K),
                   "cases": [c for c, _ in CASES], "sapwood_depth_mm": SAPWOOD_DEPTH_MM, "dx_mm": DX_MM,
                   "substeps_per_hour": SUBSTEPS_PER_HOUR, "phloem_mm": S58.T_PHLOEM, "gate_C": GATE_C,
                   "upper_C": UPPER_C},
        "bark": bark,
        "scheme_check_rel_error": round(scheme_err, 5),
        "runs": runs,
        "reference_no_flange_surface_at_air": reference,
        "verdict": {"worst_cell": worst, "no_flange_max_C": ref_max, "shift_under_crown_K": shift,
                    "alpha_crossing_sunlit_still_air": a_star,
                    "dead_bark_floor_mm_at_specified_alpha": floor_mm, "text": text},
        "ceilings": ["1D, adiabatic inner end, zero contact resistance, flange AT the capsule temperature — UPPER bounds",
                     "bark without the flange is taken at AIR temperature: its own diffuse gain is ignored, which "
                     "overstates the shift under a crown",
                     "sunlit bark not computed — no bark surface temperature in the tree",
                     "the flange's lateral band is not in 71's areas — a band darker than the radome moves the lump UP",
                     "the gate is an isotherm, not a dose (58's ceiling)",
                     "a furrow deeper than the facing plane is an air gap under the flange — its path is not computed",
                     "no frost verdict — neither 71's capsule nor the bark here radiates to the sky"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
