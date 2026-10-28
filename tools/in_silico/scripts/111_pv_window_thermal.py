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
so neither says what a dark patch of a given AREA does. This script says it, per named aperture.

MODEL — `71`'s lump and `78`'s column, imported, never re-implemented; only the absorbed power changes.
  • Two zones on `71`'s own surfaces: the window — a dark patch of aperture A_dark at α_c — and the rest of the dome
    at α_r. The dark aperture is the WINDOW's: light that enters the window and misses the cell is absorbed inside
    the lump all the same.
  • Beam, in `71`'s worst-orientation construction (the largest projection over ALL beam directions, an upper bound on
    the direct gain by construction): the crown disc projects as cos ψ and the side wall as sin ψ, and the patch sits
    in the crown, so the largest absorbed beam power over ψ is DNI · √((α_r·A_crown + Δα·A_dark)² + (α_r·D·H)²) with
    Δα = α_c − α_r — written as α_beam·A_proj, so the patch enters `71`'s balance as an effective beam absorptance.
  • Diffuse — exact within `71`'s view factor: α_diffuse = α_r + Δα·A_dark/A_exp.
  • α_c = 1.00 is the BOUND: no surface absorbs more than all the light that reaches it, and whatever the cell
    exports — energy the node stores and spends inside the same lump, or the share the radio radiates out through the
    dome — can only lower the heat; 0.90 is OURS, a dark cell with some reflection, no primary read.
  • h_c is read at `71`'s two readings, nominal and × H_C_SENSITIVITY (the correlation off its home geometry), for the
    capsule AND the cambium: `71` calls that band part of its own uncertainty, so a sentence that a window «stays under»
    holds only on the reading it names.
  • The named areas are `110`'s (its cache, `measured_form_r.r_below_which_it_cannot_by_cell_area`), and they are two
    KINDS (APERTURE_KIND): the package and the dies are cell OUTLINES — a window that exposes them is at least as large,
    so on those rows the dark aperture is a LOWER bound, the unsafe side; the flat crown and the bore are windows.
  • The largest dark aperture that keeps the worst cell (full sun, still air, the thinnest contact) under the cambium
    gate, per α_c and h_c reading: on a grid of apertures over the crown disc, linear between the two neighbours that
    bracket the gate, then FLOORED to 0.01 cm² so the one-sided sentence stays true (in-silico §When Modifying #43).

CONTROLS — the two-zone beam term against a brute force over ψ for every named aperture and α_c (a control with
α_c ≠ α_r, i.e. one that can fail on the formula); plumbing identities: A_dark = 0 reproduces `71`'s α_r row and
`78`'s α_r cell, a uniform dome (α_c = α_r = 0.70) reproduces their α 0.70 rows, and A_dark = 0 at h_c × 0.7
reproduces `71`'s cached sensitivity row — all three pass for ANY formula that returns α_r when Δα·A_dark = 0, so they
check the wiring (the third, the h_c × 0.7 path's), never the two-zone term; the crossing grid is monotone.

DIRECTION, stated first: every term inherited from `71` and `78` pushes the temperatures UP (worst orientation over
all beam directions, adiabatic base, flange at the capsule's temperature, 1D column, adiabatic inner end) and α_c = 1
does too, so every hot number is an UPPER bound and every «stays under» is sufficient within those models on the h_c
reading it names; a «does not clear» is not «crosses» — an upper bound cannot show a crossing. Two terms run the
other way and are named, not hidden: `71`'s own ⛔ ceilings (sunlit bark around the rim conducting in, ERA5 smoothing
station maxima) move the hot answer UP beyond these bounds; and a window wider than the flat crown sits on the R5
edge, which `71` models as part of a flat disc — for every named window and every crossing (none wider than the bore)
the patch is centred and its edge slopes less than 90° − ψ* at the binding angle, so a convex patch projects exactly
as its planar disc and the beam term stays the bound, while the diffuse term counts the planar disc, a few per cent
less than the curved surface. Grid points near the whole crown fall outside that condition (the edge there reaches
90°), which is why no number at the grid's far end is cached or quoted.

CAN show: per named aperture, α_c and h_c reading, the capsule's hottest hour against the EDLC rating and the
cambium's against its gate under `71`'s and `78`'s cases; the largest dark aperture that keeps the bound's cambium
under the gate.
CANNOT show: the window's optics (transmittance, its own absorption, the cavity's greenhouse — the lump is
isothermal); a cell's real absorptance; whether a window meets the ratified α ≤ 0.5 at all — that is a verdict, not a
number; the RF half of the window (its own leg, 01_03 §4).

Run:  python tools/in_silico/scripts/111_pv_window_thermal.py      # ~10 min (30 years hourly, ~300 columns)
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
PSI_GRID = 90001                 # the brute-force control's beam angles, 0–90°
# `110`'s named areas, by kind — a new key there must be classified here before this script reads it
APERTURE_KIND = {"one_package_in_the_crown_KXOB25-07X1TF": "cell_outline",
                 "four_dies_in_the_crown_XOD17-04B": "cell_outline",
                 "flat_crown_circle": "window", "bore_circle": "window"}
KIND_MEANS = {"cell_outline": "a cell outline — a window exposing it is at least as large, so the dark aperture here "
                              "is a LOWER bound",
              "window": "the window itself"}


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S78 = _load("s78_cambium", "78_flange_cambium_heat.py")
ALPHA_R = S71.ALPHA_EDGES[0]     # the specified ceiling (α ≤ 0.5, 02_01 §5.2) — `71`'s low quoted end
GATE_C = S78.GATE_C
H_C_READINGS = (1.0, S71.H_C_SENSITIVITY)


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


def beam_brute_force(geo: dict, a_dark_mm2: float, alpha_c: float, alpha_r: float = ALPHA_R) -> float:
    """The same α_beam by a maximum over sampled beam angles — the control that can fail on the two-zone term."""
    d, h = geo["dome_diameter_mm"], geo["h_over_bark_mm"]
    a_crown = math.pi * (d / 2) ** 2
    psi = np.linspace(0.0, math.pi / 2, PSI_GRID)
    proj = a_crown * np.cos(psi) + d * h * np.sin(psi)
    gain = alpha_r * proj + (alpha_c - alpha_r) * a_dark_mm2 * np.cos(psi)
    return float(gain.max() / proj.max())


def absorbed(h: dict, geo: dict, alpha_beam: float, alpha_diffuse: float, beam_on: float) -> np.ndarray:
    a_proj, a_exp = geo["a_proj_max_mm2"] * 1e-6, geo["a_exp_mm2"] * 1e-6
    return alpha_beam * beam_on * h["dni"] * a_proj + alpha_diffuse * S71.SKY_VIEW * h["dif"] * a_exp


def capsule(h: dict, geo: dict, q: np.ndarray, h_c_scale: float = 1.0) -> np.ndarray:
    return S71.solve_t_cap(h["t_air"], q, geo["a_exp_mm2"] * 1e-6, geo["dome_diameter_mm"] * 1e-3, STILL * h["u10"],
                           h_c_scale=h_c_scale)


def hc_key(scale: float) -> str:
    return "nominal" if scale == 1.0 else f"h_c_x{scale:.1f}".replace(".", "_")


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
    if set(areas) != set(APERTURE_KIND):
        raise SystemExit(f"110's named areas {sorted(areas)} are not the ones APERTURE_KIND classifies — classify them first")
    a_crown = math.pi * (geo["dome_diameter_mm"] / 2) ** 2

    # ── the control that can fail on the two-zone term: closed form ⊥ brute force over ψ ────────────────────────────
    worst_rel = 0.0
    for area, ac in itertools.product(areas.values(), ALPHA_CELL):
        cf, bf = zone_alphas(geo, area, ac)[0], beam_brute_force(geo, area, ac)
        worst_rel = max(worst_rel, abs(cf - bf) / cf)
    if worst_rel > 1e-6:
        raise SystemExit(f"two-zone beam term: closed form and brute force differ by {worst_rel:.2e}")
    print(f"  two-zone beam term: closed form = brute force over {PSI_GRID} angles to {worst_rel:.1e} (relative)")

    # ── the columns: plumbing identities, named apertures × α_c × case × h_c, and the crossing grid ─────────────────
    cols, meta = [], []

    def add(kind, area, alpha_c, case, beam_on, scale=1.0, alpha_r=ALPHA_R):
        ab, ad = zone_alphas(geo, area, alpha_c, alpha_r)
        cols.append(capsule(h, geo, absorbed(h, geo, ab, ad, beam_on), h_c_scale=scale))
        meta.append({"kind": kind, "area_mm2": area, "alpha_cell": alpha_c, "case": case, "h_c": scale,
                     "alpha_beam": ab, "alpha_diffuse": ad})

    add("control_no_window", 0.0, 1.0, "sunlit", 1.0)
    add("control_uniform", a_crown, UNIFORM_CONTROL_ALPHA, "sunlit", 1.0, alpha_r=UNIFORM_CONTROL_ALPHA)
    add("control_no_window_low_h_c", 0.0, 1.0, "sunlit", 1.0, S71.H_C_SENSITIVITY)
    for name, area in areas.items():
        for ac in ALPHA_CELL:
            for scale in H_C_READINGS:
                add(name, area, ac, "sunlit", 1.0, scale)
            add(name, area, ac, "shaded", 0.0)
    n_both = len(cols)          # columns run on both bark sides; the grid below runs on the thin one only
    grid = [float(x) for x in np.arange(0.0, a_crown, AREA_GRID_STEP_MM2)] + [a_crown]
    for ac, scale in itertools.product(ALPHA_CELL, H_C_READINGS):
        for area in grid:
            add("grid", area, ac, "sunlit", 1.0, scale)

    # ── plumbing identities on the capsule: 71's own rows ────────────────────────────────────────────────────────────
    want_r = c71["hot_bound"]["sunlit"][f"{ALPHA_R:.2f}"][f"{STILL:.1f}"]["t_cap_max_c"]
    want_u = c71["hot_bound"]["sunlit"][f"{UNIFORM_CONTROL_ALPHA:.2f}"][f"{STILL:.1f}"]["t_cap_max_c"]
    sens = c71["hot_bound_h_c_sensitivity"]
    if sens["h_c_scale"] != S71.H_C_SENSITIVITY:
        raise SystemExit(f"71's cached h_c sensitivity is × {sens['h_c_scale']}, its code says × {S71.H_C_SENSITIVITY}")
    want_l = sens["sunlit_still_air"][f"{ALPHA_R:.2f}"]["t_cap_max_c"]
    got_r, got_u, got_l = (round(float(cols[i].max()), 1) for i in (0, 1, 2))
    if abs(got_r - want_r) > 0.05 or abs(got_u - want_u) > 0.05 or abs(got_l - want_l) > 0.05:
        raise SystemExit(f"capsule identity failed: no window {got_r} vs 71's {want_r}; uniform {got_u} vs {want_u}; "
                         f"no window at h_c × {S71.H_C_SENSITIVITY} {got_l} vs {want_l}")
    print(f"  plumbing identities on 71: no window {got_r} °C (cache {want_r}) · uniform α {UNIFORM_CONTROL_ALPHA:.2f} "
          f"{got_u} °C (cache {want_u}) · no window at h_c × {S71.H_C_SENSITIVITY} {got_l} °C (cache {want_l})")

    # ── the cambium: 78's column — every column on the thin side, the non-grid ones on the thick side too ────────────
    cam_thin = S78.run(np.column_stack(cols), S78.layers(bark["thin_mm"]), bark["thin_mm"] + S78.S58.T_PHLOEM,
                       S78.SUBSTEPS_PER_HOUR)
    cam_thick = S78.run(np.column_stack(cols[:n_both]), S78.layers(bark["thick_mm"]),
                        bark["thick_mm"] + S78.S58.T_PHLOEM, S78.SUBSTEPS_PER_HOUR)
    cam = {"thin": cam_thin, "thick": cam_thick}

    def c78_cell(alpha, side):
        return next(r for r in c78["runs"] if (r["case"], r["alpha"], r["wind_k"], r["bark_side"])
                    == ("sunlit", alpha, STILL, side))
    for col, alpha in ((0, ALPHA_R), (1, UNIFORM_CONTROL_ALPHA)):
        for side in cam:
            got, want = round(float(cam[side][:, col].max()), 2), c78_cell(alpha, side)["cambium_max_C"]
            if abs(got - want) > 0.005:
                raise SystemExit(f"cambium identity failed ({side}, α {alpha}): {got} vs 78's {want}")
    print("  plumbing identities on 78: both bark sides reproduce its cached cambium maxima at α "
          f"{ALPHA_R:.2f} and {UNIFORM_CONTROL_ALPHA:.2f}")

    # ── the named apertures ──────────────────────────────────────────────────────────────────────────────────────────
    rating = c71["rating_c"]["edlc_operating_max"]
    named = {}
    for i, m in enumerate(meta[:n_both]):
        if m["kind"].startswith("control"):
            continue
        cell = named.setdefault(m["kind"], {"area_cm2": round(m["area_mm2"] / 100.0, 4),
                                            "kind": APERTURE_KIND[m["kind"]],
                                            "kind_means": KIND_MEANS[APERTURE_KIND[m["kind"]]], "by_alpha_cell": {}})
        by = cell["by_alpha_cell"].setdefault(f"{m['alpha_cell']:.2f}", {
            "alpha_beam": round(m["alpha_beam"], 6), "alpha_diffuse": round(m["alpha_diffuse"], 6)})
        t_max = float(cols[i].max())
        row = {"t_cap_max_c": round(t_max, 1), "margin_to_rating_k": round(rating - t_max, 1),
               "at": str(times[int(cols[i].argmax())])[:16]}
        for side in cam:
            s = S78.summarise(cam[side][:, i], times)
            row[f"cambium_{side}"] = {k: s[k] for k in ("cambium_max_C", "at", "hours_above_gate")}
        by[m["case"] if m["case"] == "shaded" else f"sunlit_{hc_key(m['h_c'])}"] = row

    # ── the crossing: the largest dark aperture that keeps the worst cell under the gate ─────────────────────────────
    crossing = {}
    for ac, scale in itertools.product(ALPHA_CELL, H_C_READINGS):
        idx = [i for i, m in enumerate(meta) if m["kind"] == "grid" and m["alpha_cell"] == ac and m["h_c"] == scale]
        xs = [meta[i]["area_mm2"] for i in idx]
        ys = [float(cam["thin"][:, i].max()) for i in idx]
        if any(b < a - 1e-9 for a, b in itertools.pairwise(ys)):
            raise SystemExit(f"the crossing grid is not monotone in the aperture (α_c {ac}, h_c × {scale})")
        x = S78.crossing(xs, ys, GATE_C)
        # S78.crossing returns the interpolated aperture rounded to 0.001 mm² — the floor to 0.01 cm² below is taken
        # on that value, so a true crossing within 0.0005 mm² under a whole mm² could floor one step high (not met here)
        crossing.setdefault(f"{ac:.2f}", {})[hc_key(scale)] = {
            "largest_dark_aperture_under_gate_cm2": None if x is None else math.floor(x) / 100.0,
            "crossing_interpolated_mm2": x,
            "is_nowhere_on_the_crown": x is None, "is_already_at_no_window": x == xs[0],
            "cambium_max_C_at_no_window": round(ys[0], 2)}

    # ── the verdict, from the data ───────────────────────────────────────────────────────────────────────────────────
    def cell(name, ac, key):
        return named[name]["by_alpha_cell"][f"{ac:.2f}"][key]

    bound = f"{ALPHA_CELL[0]:.2f}"
    k_lo = hc_key(S71.H_C_SENSITIVITY)
    hottest = {k: max(cell(n, ALPHA_CELL[0], f"sunlit_{k}")["t_cap_max_c"] for n in named) for k in ("nominal", k_lo)}

    def under(k):
        return [n for n in named if cell(n, ALPHA_CELL[0], f"sunlit_{k}")["cambium_thin"]["hours_above_gate"] == 0]

    xb = {k: crossing[bound][k]["largest_dark_aperture_under_gate_cm2"] for k in ("nominal", k_lo)}
    text = (f"With the rest of the dome at α {ALPHA_R:.2f} and the window at α_c {bound} (the bound), no named window "
            f"brings the capsule to the {rating:.0f} °C EDLC rating — at most {hottest['nominal']:.1f} °C, "
            f"{hottest[k_lo]:.1f} °C with h_c × {S71.H_C_SENSITIVITY}. The cambium under the flange's thinnest contact, "
            f"in full sun and still air, stays under its {GATE_C:.0f} °C gate at the nominal h_c for "
            f"{', '.join(under('nominal')) or 'no named window'}, and with h_c × {S71.H_C_SENSITIVITY} for "
            f"{', '.join(under(k_lo)) or 'no named window'}; on the bound the largest dark aperture that keeps it under "
            f"is {xb['nominal']:.2f} cm² at the nominal h_c and {xb[k_lo]:.2f} cm² with h_c × {S71.H_C_SENSITIVITY} "
            f"(floored; grid {AREA_GRID_STEP_MM2 / 100.0:.2f} cm²). Above those the bound does not clear the gate — "
            f"which is not a crossing. Every number is an UPPER bound inherited from 71 and 78.")
    print(f"\n  → {text}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "question": "how much a dark PV window in the radome's crown heats the capsule and the cambium under the flange, "
                    "per named aperture, the rest of the dome at the specified finish",
        "method": "71's lumped capsule balance and 78's 1D cambium column, imported; the absorbed power of a two-zone "
                  "dome in 71's worst-orientation construction (beam) and its view factor (diffuse); h_c at 71's two "
                  "readings for the capsule and the cambium",
        "inputs": {"alpha_radome": ALPHA_R, "alpha_cell_readings": list(ALPHA_CELL),
                   "alpha_cell_readings_are": {"1.00": "bound — no surface absorbs more than all the light reaching "
                                                       "it, and any energy the cell exports only lowers the heat",
                                               "0.90": "ours — a dark cell with some reflection, no primary read"},
                   "h_c_readings": list(H_C_READINGS), "geometry_71": geo, "crown_disc_mm2": round(a_crown, 2),
                   "bark": bark, "gate_C": GATE_C, "edlc_rating_c": rating, "wind_k": STILL,
                   "named_apertures_from": "110 measured_form_r", "area_grid_step_mm2": AREA_GRID_STEP_MM2,
                   "crossing_rounding": "floored to 0.01 cm² (one-sided «stays under», modifying #43)"},
        "controls": {"two_zone_beam_closed_form_vs_brute_force_rel": worst_rel, "psi_grid": PSI_GRID,
                     "plumbing_capsule_no_window_c": got_r, "plumbing_capsule_uniform_c": got_u,
                     "plumbing_capsule_no_window_low_h_c_c": got_l,
                     "uniform_control_alpha": UNIFORM_CONTROL_ALPHA,
                     "plumbing_note": "the three plumbing identities pass for any formula returning α_r when "
                                      "Δα·A_dark = 0 — they check the wiring, not the two-zone term"},
        "named_windows": named,
        "crossing_worst_cell_thin_sunlit_still": crossing,
        "verdict": text,
        "not_seen": ["the window's optics — transmittance, its own absorption, the cavity's greenhouse (isothermal lump)",
                     "a cell's real absorptance (α_c 0.90 is ours)",
                     "the two cell-outline rows are LOWER bounds on the dark aperture: a window exposing the outline "
                     "is at least as large — read them against the crossing",
                     "the R5 edge: a window wider than the flat crown sits on it, and 71 models it as part of a flat "
                     "disc — for every named window and every crossing (none wider than the bore) the beam term stays "
                     "the bound (a centred convex patch, its edge sloping less than 90° − ψ* at the binding angle, "
                     "projects as its planar disc), the diffuse term counts the planar disc, a few per cent less than "
                     "the curved surface; grid points near the whole crown fall outside that condition, so no number "
                     "at the grid's far end is cached",
                     "71's own ceilings move the hot answer UP beyond these bounds: sunlit bark around the rim "
                     "conducting in, ERA5 smoothing station maxima",
                     "whether a window meets the ratified α ≤ 0.5 — a verdict, not a number",
                     "the RF half of the window (01_03 §4)"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
