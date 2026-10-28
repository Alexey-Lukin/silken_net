#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
111 — How much does a dark PV cell behind a window in the radome's crown heat the capsule and the cambium under the
flange, when the rest of the dome keeps the specified finish α ≤ 0.5? (00_07 HW.54, leg «тепловий прогін `71` і `78`
з α комірки на грані — дужкою, доки комірку не обрано».)

QUESTION. The radome's finish is specified as a solar absorptance α ≤ 0.5 for the whole service life (02_01 §5.2), on
two grounds: the EDLC's margin at the dark end is of the order of the model's own uncertainty (`71`), and the cambium
under the flange's thinnest contact reaches its gate past α ≈ 0.66 (`78`, interpolated on `71`'s α grid). The only
PV form the desk kept is a cell INSIDE the capsule behind a window in the dome's crown (01_03 §4 ⊕ Р3(б)). A cell is
an absorber by design, so the window reads as a dark patch — but `71` and `78` take the dome as ONE uniform finish,
so neither says what a dark patch of a given AREA does. This script says it, per named window area.

MODEL — `71`'s lump and `78`'s column, imported, never re-implemented; only the absorbed power changes.
  • Two zones on `71`'s own surfaces: the window — a dark patch of aperture A_dark at α_c — and the rest of the dome
    at α_r. The aperture is the WINDOW's, not the cell's active area: light that enters the window and misses the
    cell is absorbed inside the lump all the same.
  • Beam, in `71`'s worst-orientation construction (the largest projection over ALL beam directions, an upper bound on
    the direct gain by construction): the crown disc projects as cos ψ and the side wall as sin ψ, and the patch sits
    in the crown, so the largest absorbed beam power over ψ is DNI · √((α_r·A_crown + Δα·A_dark)² + (α_r·D·H)²) with
    Δα = α_c − α_r — written as α_beam·A_proj, so the patch enters `71`'s balance as an effective beam absorptance.
  • Diffuse — exact within `71`'s view factor: α_diffuse = α_r + Δα·A_dark/A_exp.
  • α_c = 1.00 is the BOUND (everything that enters the window stays in the lump as heat: the cell exports its η
    only while charging, and the node turns those microwatts into heat inside the same lump; when the store is full
    charging stops — 01_03 §4's own derivation); 0.90 is OURS, a dark cell with some reflection, no primary read.
  • The named apertures are `110`'s (its cache, `measured_form_r.r_below_which_it_cannot_by_cell_area`): one package
    in the crown, four dies in the crown, the whole flat crown, the whole bore — never typed here.
  • The window's largest dark area that keeps the worst cell (full sun, still air, the thinnest contact) under the
    cambium gate: on a grid of apertures over the crown disc, linear between the two neighbours that bracket the gate
    — the grid step is printed as the resolution.

CONTROLS — identities, asserted before any reading: A_dark = 0 reproduces `71`'s α_r row and `78`'s α_r cell; a
uniform dome (α_c = α_r = 0.70) reproduces `71`'s and `78`'s α 0.70 rows; the crossing grid is monotone.

DIRECTION, stated first: every term inherited from `71` and `78` pushes the temperatures UP (worst orientation over
all beam directions, adiabatic base, flange at the capsule's temperature, 1D column, adiabatic inner end) and
α_c = 1 does too, so every hot number is an UPPER bound and every «stays below» is sufficient within those models;
a «reaches the gate» is not established by an upper bound — it says the bound does not clear it.

CAN show: per named aperture and α_c, the capsule's hottest hour against the EDLC rating and the cambium's against
its gate under `71`'s and `78`'s cases; the largest dark aperture that keeps the bound's cambium under the gate.
CANNOT show: the window's optics (transmittance, its own absorption, the greenhouse of the cavity — the lump is
isothermal); a cell's real absorptance; the R5 edge as a curved surface (`71` takes the crown as a flat disc of the
dome's diameter, and a window wider than the flat crown sits on that edge); whether a window meets the ratified
α ≤ 0.5 at all — that is a verdict, not a number; the RF half of the window (its own leg, 01_03 §4).

Run:  python tools/in_silico/scripts/111_pv_window_thermal.py      # a few minutes (30 years hourly, one column set per bark side)
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
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Capsule and cambium temperature with a dark photovoltaic window in the radome's crown, per window area, the rest of the dome at the specified finish (upper bound)."  # its row in the paper SI (72): English, no repo jargon

OUT_DIR = CACHE_DIR / "thermal"
OUT = OUT_DIR / "pv_window_thermal.json"
PV_CACHE = CACHE_DIR / "kinetics" / "winter_pv_autonomy.json"
SCRIPTS = Path(__file__).resolve().parent

ALPHA_CELL = (1.00, 0.90)        # the bound, then ours — see docstring
UNIFORM_CONTROL_ALPHA = 0.70     # a uniform dome at a grid row of `71` and `78`
AREA_GRID_STEP_MM2 = 10.0        # the crossing grid over the crown disc
STILL = 0.0                      # `71`'s still-air bound


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S78 = _load("s78_cambium", "78_flange_cambium_heat.py")
ALPHA_R = S71.ALPHA_EDGES[0]     # the specified ceiling (α ≤ 0.5, 02_01 §5.2) — `71`'s low quoted end
GATE_C = S78.GATE_C


def zone_alphas(geo: dict, a_dark_mm2: float, alpha_c: float, alpha_r: float = ALPHA_R) -> tuple[float, float]:
    """(α_beam, α_diffuse) of the two-zone dome on `71`'s surfaces; a_dark = 0 or α_c = α_r give α_r for both."""
    d, h = geo["dome_diameter_mm"], geo["h_over_bark_mm"]
    a_crown = math.pi * (d / 2) ** 2
    if a_dark_mm2 > a_crown + 1e-9:
        raise ValueError(f"a dark aperture of {a_dark_mm2:.1f} mm² is larger than the crown disc ({a_crown:.1f})")
    da = alpha_c - alpha_r
    beam = math.hypot(alpha_r * a_crown + da * a_dark_mm2, alpha_r * d * h) / math.hypot(a_crown, d * h)
    diffuse = alpha_r + da * a_dark_mm2 / geo["a_exp_mm2"]
    return beam, diffuse


def absorbed(h: dict, geo: dict, alpha_beam: float, alpha_diffuse: float, beam_on: float) -> np.ndarray:
    a_proj, a_exp = geo["a_proj_max_mm2"] * 1e-6, geo["a_exp_mm2"] * 1e-6
    return alpha_beam * beam_on * h["dni"] * a_proj + alpha_diffuse * S71.SKY_VIEW * h["dif"] * a_exp


def capsule(h: dict, geo: dict, q: np.ndarray, h_c_scale: float = 1.0) -> np.ndarray:
    return S71.solve_t_cap(h["t_air"], q, geo["a_exp_mm2"] * 1e-6, geo["dome_diameter_mm"] * 1e-3, STILL * h["u10"],
                           h_c_scale=h_c_scale)


def main() -> int:
    banner("HW.54 — a dark PV window in the radome's crown: capsule and cambium, per window area (upper bound)")
    h = S71.load_hours()
    geo = S71.geometry()
    times = h["time"]
    bark = S78.bark_bracket()
    c71 = json.loads((OUT_DIR / "capsule_envelope.json").read_text(encoding="utf-8"))
    c78 = json.loads((OUT_DIR / "flange_cambium_heat.json").read_text(encoding="utf-8"))
    areas = {name: v["area_cm2"] * 100.0 for name, v in
             json.loads(PV_CACHE.read_text(encoding="utf-8"))["measured_form_r"]["r_below_which_it_cannot_by_cell_area"].items()}
    a_crown = math.pi * (geo["dome_diameter_mm"] / 2) ** 2

    # ── the columns: named apertures × α_c × case, the two identity controls, and the crossing grid ──────────────────
    cols, meta = [], []

    def add(kind, area, alpha_c, case, beam_on, alpha_r=ALPHA_R):
        ab, ad = zone_alphas(geo, area, alpha_c, alpha_r)
        cols.append(capsule(h, geo, absorbed(h, geo, ab, ad, beam_on)))
        meta.append({"kind": kind, "area_mm2": area, "alpha_cell": alpha_c, "case": case,
                     "alpha_beam": ab, "alpha_diffuse": ad})

    add("control_no_window", 0.0, 1.0, "sunlit", 1.0)
    add("control_uniform", a_crown, UNIFORM_CONTROL_ALPHA, "sunlit", 1.0, alpha_r=UNIFORM_CONTROL_ALPHA)
    for name, area in areas.items():
        for ac in ALPHA_CELL:
            for case, beam_on in S78.CASES:
                add(name, area, ac, case, beam_on)
    grid = [float(x) for x in np.arange(0.0, a_crown, AREA_GRID_STEP_MM2)] + [a_crown]
    for ac in ALPHA_CELL:
        for area in grid:
            add("grid", area, ac, "sunlit", 1.0)

    # ── controls on the capsule: 71's own rows ────────────────────────────────────────────────────────────────────────
    want_r = c71["hot_bound"]["sunlit"][f"{ALPHA_R:.2f}"][f"{STILL:.1f}"]["t_cap_max_c"]
    want_u = c71["hot_bound"]["sunlit"][f"{UNIFORM_CONTROL_ALPHA:.2f}"][f"{STILL:.1f}"]["t_cap_max_c"]
    got_r, got_u = round(float(cols[0].max()), 1), round(float(cols[1].max()), 1)
    if abs(got_r - want_r) > 0.05 or abs(got_u - want_u) > 0.05:
        raise SystemExit(f"capsule identity failed: no window {got_r} vs 71's {want_r}; uniform {got_u} vs {want_u}")
    print(f"  identities on 71: no window {got_r} °C (cache {want_r}) · uniform α {UNIFORM_CONTROL_ALPHA:.2f} "
          f"{got_u} °C (cache {want_u})")

    # ── the cambium: 78's column over every capsule series, both bark sides ──────────────────────────────────────────
    stack = np.column_stack(cols)
    cam = {side: S78.run(stack, S78.layers(b), b + S78.S58.T_PHLOEM, S78.SUBSTEPS_PER_HOUR)
           for side, b in (("thin", bark["thin_mm"]), ("thick", bark["thick_mm"]))}

    def c78_cell(alpha, side):
        return next(r for r in c78["runs"] if (r["case"], r["alpha"], r["wind_k"], r["bark_side"])
                    == ("sunlit", alpha, STILL, side))
    for col, alpha in ((0, ALPHA_R), (1, UNIFORM_CONTROL_ALPHA)):
        for side in cam:
            got, want = round(float(cam[side][:, col].max()), 2), c78_cell(alpha, side)["cambium_max_C"]
            if abs(got - want) > 0.005:
                raise SystemExit(f"cambium identity failed ({side}, α {alpha}): {got} vs 78's {want}")
    print("  identities on 78: both bark sides reproduce its cached cambium maxima at α "
          f"{ALPHA_R:.2f} and {UNIFORM_CONTROL_ALPHA:.2f}")

    # ── the named apertures ──────────────────────────────────────────────────────────────────────────────────────────
    rating = c71["rating_c"]["edlc_operating_max"]
    named = {}
    for i, m in enumerate(meta):
        if m["kind"] in ("control_no_window", "control_uniform", "grid"):
            continue
        cell = named.setdefault(m["kind"], {"area_cm2": round(m["area_mm2"] / 100.0, 4), "by_alpha_cell": {}})
        by = cell["by_alpha_cell"].setdefault(f"{m['alpha_cell']:.2f}", {
            "alpha_beam": round(m["alpha_beam"], 4), "alpha_diffuse": round(m["alpha_diffuse"], 4)})
        t_max = float(cols[i].max())
        row = {"t_cap_max_c": round(t_max, 1), "margin_to_rating_k": round(rating - t_max, 1),
               "at": str(times[int(cols[i].argmax())])[:16]}
        for side in cam:
            s = S78.summarise(cam[side][:, i], times)
            row[f"cambium_{side}"] = {k: s[k] for k in ("cambium_max_C", "at", "hours_above_gate")}
        if m["case"] == "sunlit":
            ab, ad = m["alpha_beam"], m["alpha_diffuse"]
            row["t_cap_max_c_h_c_x0_7"] = round(float(capsule(h, geo, absorbed(h, geo, ab, ad, 1.0),
                                                              h_c_scale=S71.H_C_SENSITIVITY).max()), 1)
        by[m["case"]] = row

    # ── the crossing: the largest dark aperture that keeps the worst cell under the gate ─────────────────────────────
    crossing = {}
    for ac in ALPHA_CELL:
        idx = [i for i, m in enumerate(meta) if m["kind"] == "grid" and m["alpha_cell"] == ac]
        xs = [meta[i]["area_mm2"] for i in idx]
        ys = [float(cam["thin"][:, i].max()) for i in idx]
        if any(b < a - 1e-9 for a, b in itertools.pairwise(ys)):
            raise SystemExit(f"the crossing grid is not monotone in the aperture (α_c {ac})")
        x = S78.crossing(xs, ys, GATE_C)
        crossing[f"{ac:.2f}"] = {
            "largest_dark_aperture_under_gate_cm2": None if x is None else round(x / 100.0, 2),
            "is_nowhere_on_the_crown": x is None,
            "cambium_max_C_at_no_window": round(ys[0], 2), "cambium_max_C_at_whole_crown": round(ys[-1], 2)}

    # ── the verdict, from the data ───────────────────────────────────────────────────────────────────────────────────
    def cell(name, ac, case="sunlit"):
        return named[name]["by_alpha_cell"][f"{ac:.2f}"][case]

    bound = f"{ALPHA_CELL[0]:.2f}"
    under = [n for n in named if cell(n, ALPHA_CELL[0])["cambium_thin"]["hours_above_gate"] == 0]
    over = [n for n in named if n not in under]
    hottest = max(cell(n, ALPHA_CELL[0])["t_cap_max_c"] for n in named)
    hottest_x07 = max(cell(n, ALPHA_CELL[0])["t_cap_max_c_h_c_x0_7"] for n in named)
    xb = crossing[bound]["largest_dark_aperture_under_gate_cm2"]
    text = (f"With the rest of the dome at α {ALPHA_R:.2f} and the window at α_c {bound} (the bound), the capsule's "
            f"hottest hour stays under the {rating:.0f} °C EDLC rating for every named window — at most "
            f"{hottest:.1f} °C ({hottest_x07:.1f} °C with h_c × {S71.H_C_SENSITIVITY}). The cambium under the flange's "
            f"thinnest contact stays under its {GATE_C:.0f} °C gate in full sun and still air for "
            f"{', '.join(under) if under else 'no named window'}"
            f"{'; it does not clear it for ' + ', '.join(over) if over else ''}. "
            + (f"On the bound the largest dark aperture that keeps it under is ≈ {xb:.2f} cm² "
               f"(grid {AREA_GRID_STEP_MM2 / 100.0:.2f} cm²)." if xb is not None else
               "On the bound no dark aperture up to the whole crown reaches the gate.")
            + " Every number is an UPPER bound inherited from 71 and 78.")
    print(f"\n  → {text}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "question": "how much a dark PV window in the radome's crown heats the capsule and the cambium under the flange, "
                    "per named window aperture, the rest of the dome at the specified finish",
        "method": "71's lumped capsule balance and 78's 1D cambium column, imported; the absorbed power of a two-zone "
                  "dome in 71's worst-orientation construction (beam) and its view factor (diffuse)",
        "inputs": {"alpha_radome": ALPHA_R, "alpha_cell_readings": list(ALPHA_CELL),
                   "alpha_cell_readings_are": {"1.00": "bound — everything entering the window stays as heat",
                                               "0.90": "ours — a dark cell with some reflection, no primary read"},
                   "geometry_71": geo, "crown_disc_mm2": round(a_crown, 2), "bark": bark, "gate_C": GATE_C,
                   "edlc_rating_c": rating, "wind_k": STILL, "named_apertures_from": "110 measured_form_r",
                   "area_grid_step_mm2": AREA_GRID_STEP_MM2},
        "controls": {"capsule_no_window_c": got_r, "capsule_uniform_c": got_u,
                     "uniform_control_alpha": UNIFORM_CONTROL_ALPHA},
        "named_windows": named,
        "crossing_worst_cell_thin_sunlit_still": crossing,
        "verdict": text,
        "not_seen": ["the window's optics — transmittance, its own absorption, the cavity's greenhouse (isothermal lump)",
                     "a cell's real absorptance (α_c 0.90 is ours)",
                     "71 takes the crown as a flat disc of the dome's diameter: a window wider than the flat crown "
                     "sits on the curved R5 edge, whose projection this construction does not follow",
                     "whether a window meets the ratified α ≤ 0.5 — a verdict, not a number",
                     "the RF half of the window (01_03 §4)",
                     "every ceiling of 71 and 78 (sunlit bark, ERA5 smoothing, 1D, adiabatic ends)"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
