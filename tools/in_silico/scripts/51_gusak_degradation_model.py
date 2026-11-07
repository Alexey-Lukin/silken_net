#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.3 — Гусак degradation models: Arrhenius aging + Kirkendall diffusion + H7/s6 press-fit.
HW.37 — EDLC endurance-hours (Eaton KR / KEMET FG0H474ZF) reuses the generalized Arrhenius
kernel below + a sibling vendor voltage-doubling model (4th analytical model, added 2026-09-09).

Four analytical models for 20-year anchor/component integrity (школа Гусака):

1. Arrhenius accelerated aging: lab weeks → field years equivalence (Ti corrosion, HW.3)
2. Kirkendall ion diffusion: V³⁺/Al³⁺ release through TiO₂ passive layer
3. H7/s6 press-fit interference window: min/max натяг vs ΔCTE
4. EDLC endurance-hours: vendor temperature+voltage life-doubling rule (HW.37)

All pure analytical (numpy), no FEA needed.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    ANCHOR_SERVICE_LIFE_YEARS,
    E_PEEK_PA,
    EATON_KR_CELLS_IN_SERIES,
    EATON_KR_LIFE_ROWS,
    EATON_KR_RATED_HOURS,
    EATON_KR_RATED_TEMP_C,
    EATON_KR_RATED_VOLTAGE_V,
    FIELD_TEMPS_C,
    H7S6_INTERF_DIA_MAX_UM,
    H7S6_INTERF_DIA_MIN_UM,
    KEMET_FG_RATED_HOURS,
    KEMET_FG_RATED_TEMP_C,
    KEMET_FG_RATED_VOLTAGE_V,
    KINETICS_DIR,
    NU_PEEK,
    PS5006_FIG1_30PCT_1V8,
    PS5006_FIG1_30PCT_2V5,
    PS5006_FIG1_50PCT_2V5,
    R_INTERFACE_M,
    R_OUTER_M,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
    THERMAL_DOUBLING_INTERVAL_K,
    VBAT_OV_RATIFIED_V,
    VOLTAGE_DOUBLING_UNSOURCED_0V2_V,
    VOLTAGE_DOUBLING_UNSOURCED_0V4_V,
)
from lib.mechanics import thick_wall_hoop
from lib.utils import banner

SI_DESCRIPTION = "Component degradation models: Arrhenius ageing, Kirkendall diffusion, H7/s6 press-fit and EDLC endurance hours."  # its row in the paper SI (72): English, no repo jargon

OUT_JSON = KINETICS_DIR / "gusak_degradation.json"


def arrhenius_aging(
    t_field_k: float = 288.15,
    t_lab_k: float = 313.15,
    ea_range_ev=(0.7, 0.85, 1.0),
    lab_weeks=(4, 8, 12),
    weeks_per_year: float = 52.0,
    label: str = "Ti corrosion",
):
    """Arrhenius acceleration: lab weeks at T_lab -> field years at T_field.

    Generalized 2026-09-09 (HW.37): was hardcoded to the Ti-corrosion T_field/T_lab/Ea
    triple with no parameters at all — this signature now accepts them, so the SAME
    continuous exp(Ea/kB*(1/T_field-1/T_lab)) kernel is reusable for any fixed-Ea
    Arrhenius problem. Defaults reproduce the ORIGINAL Ti-corrosion call exactly
    (HW.3/HW.3.IS numbers unchanged — main() below still calls this with no args).

    NOTE this is NOT the model HW.37's EDLC capacitor endurance-hours needs (see
    capacitor_life_hours() below): vendor capacitor datasheets use a discrete "life
    doubles every dT/dV" step-rule, which is a DIFFERENT functional form from this
    continuous exp() kernel (a fixed Ea integrated continuously over a 60 degree span
    does not reproduce a flat "2x per 10 degrees" applied uniformly — verified while
    generalizing this function, not a bug in either model).
    """
    banner(f"1. Arrhenius Accelerated Aging — {label}")

    kb_ev = 8.617e-5  # eV/K

    print(f"  T_field = {t_field_k - 273.15:.0f}°C ({t_field_k:.0f} K)")
    print(f"  T_lab   = {t_lab_k - 273.15:.0f}°C ({t_lab_k:.0f} K)")
    print()
    header = "  ".join(f"{w} wks" for w in lab_weeks)
    print(f"  {'Ea (eV)':>8s}  {header}")
    print(f"  {'-' * 36}")

    results = {}
    for ea in ea_range_ev:
        accel = np.exp(ea / kb_ev * (1 / t_field_k - 1 / t_lab_k))
        equiv = {}
        for weeks in lab_weeks:
            years = weeks / weeks_per_year * accel
            equiv[weeks] = round(years, 1)
        row = "  ".join(f"{equiv[w]:>6}" for w in lab_weeks)
        print(f"  {ea:>8.2f}  {row}  years")
        results[str(ea)] = equiv

    return results


FIELD_SERIES_CSV = REPO_ROOT / "tools/in_silico/data/era5_cherkasy/daily_t2m_mean_1991_2020.csv"

# The one open reading of an apparent Ea for Ti-6Al-4V corrosion found on 2026-09-24 — in a FOREIGN role
# (§When Modifying #10): Icorr from Tafel in pH 1.5 brine (Cl⁻ 128 g/L) under 12 MPa with H2S/CO2,
# 23-100 °C (Sci. Rep. 2022, 12, 16586; doi 10.1038/s41598-022-21047-0, Fig. 18). Not our medium and
# not our quantity (ion release from a passive film in mild sap), so it never enters the bracket; it
# is carried as the PRICE of the bracket having no source: an order lower, it shrinks the equivalence.
EA_FOREIGN_READING_EV = 8.52e3 / 96485.332  # 8.52 kJ/mol → eV per particle (F = N_A·e)


def _freeze_thaw(rows: list[str]) -> dict:
    """Per-winter frost statistics from the same daily series (FMEA #26, 00_07 HW.36)."""
    import collections

    frost: collections.Counter = collections.Counter()
    cross: collections.Counter = collections.Counter()
    prev = None
    coldest = (999.0, "")
    for r in rows:
        date, val = r.split(",")[0], float(r.split(",")[1])
        year = date[:4]
        if val < 0.0:
            frost[year] += 1
        if prev is not None and (prev < 0.0) != (val < 0.0):
            cross[year] += 1
        if val < coldest[0]:
            coldest = (val, date)
        prev = val
    years = sorted(set(frost) | set(cross))
    fd = sorted(frost[y] for y in years)
    return {"years": len(years),
            "years_with_no_frost_day": [y for y in years if frost[y] == 0],
            "frost_days_per_year": {"min": fd[0], "median": fd[len(fd) // 2], "max": fd[-1]},
            "zero_crossings_per_year_min": min(cross[y] for y in years),
            "coldest_daily_mean_c": coldest[0], "coldest_date": coldest[1],
            "days_below_minus20c": sum(1 for r in rows if float(r.split(",")[1]) < -20.0),
            "reading": ("every one of the 30 winters freezes, so the OCCURRENCE half of FMEA #26's "
                        "`O` is measured, not assumed — what stays open is whether the socket pocket "
                        "HOLDS water, i.e. drainage (02_02 §4.4). ⛔ Daily means UNDER-count crossings "
                        "(nights are colder and are not in this series); and the coldest daily mean "
                        "approaches the EDLC's -25 °C rated floor (00_07 HW.37), which is a SECOND "
                        "question this series raises and does not answer")}


def arrhenius_field_temperature(
    ea_range_ev=(0.7, 0.85, 1.0),
    t_field_assumed_k: float = 288.15,
    t_lab_k: float = 313.15,
    target_years: float = 5.0,
    target_weeks: int = 12,
):
    """The field temperature the equivalence above ASSUMED (15 °C, no source) against the one a
    30-year daily series implies.

    The right quantity is not the mean temperature but the ARRHENIUS-EFFECTIVE one,
    T_eff = −(Ea/k)/ln⟨exp(−Ea/kT)⟩ — a rate averages over the year with warm days dominating.
    CAN catch: an assumed T_field that is warmer than the series (then the years above are
    over-claimed) — asserted per Ea. CANNOT catch: stem ≠ air and frost ≠ slow liquid; both only
    lower the true T_eff, so the series' T_eff is an UPPER bound and the years a LOWER bound
    (data README). Nor does it say anything about Ea itself — which stays the unsourced input.
    """
    banner("1b. Arrhenius field temperature — ERA5 1991-2020 daily series vs the assumed 15 °C")
    kb_ev = 8.617e-5
    rows = FIELD_SERIES_CSV.read_text(encoding="utf-8").splitlines()[1:]
    t_k = np.array([float(r.split(",")[1]) for r in rows]) + 273.15

    def t_eff(ea: float) -> float:
        return float(-ea / kb_ev / np.log(np.mean(np.exp(-ea / (kb_ev * t_k)))))

    def years(ea: float, weeks: float, t_field: float) -> float:
        return float(weeks / 52.0 * np.exp(ea / kb_ev * (1 / t_field - 1 / t_lab_k)))

    def break_even_ea(t_field_of) -> float:
        lo, hi = 0.05, 2.0  # bisection on a monotone function of Ea (all |ΔT| > 0 here)
        for _ in range(200):
            mid = 0.5 * (lo + hi)
            if years(mid, target_weeks, t_field_of(mid)) < target_years:
                lo = mid
            else:
                hi = mid
        return round(0.5 * (lo + hi), 3)

    per_ea = {}
    for ea in ea_range_ev:
        te = t_eff(ea)
        assert te <= t_field_assumed_k + 0.05, (
            f"Ea {ea}: T_eff {te - 273.15:.2f} °C is WARMER than the assumed "
            f"{t_field_assumed_k - 273.15:.0f} °C — the equivalence above over-claims years")
        per_ea[str(ea)] = {
            "t_eff_c": round(te - 273.15, 2),
            "years_at_t_eff": {str(w): round(years(ea, w, te), 1) for w in (4, 8, 12)},
            "years_at_assumed": {str(w): round(years(ea, w, t_field_assumed_k), 1) for w in (4, 8, 12)},
        }
        print(f"  Ea {ea:.2f} eV: T_eff = {te - 273.15:5.2f} °C · 12 wk ≈ "
              f"{years(ea, 12, te):.1f} yr (vs {years(ea, 12, t_field_assumed_k):.1f} at 15 °C)")
    foreign = EA_FOREIGN_READING_EV
    out = {
        "series": str(FIELD_SERIES_CSV.relative_to(REPO_ROOT)),
        "n_days": int(t_k.size),
        "mean_c": round(float(t_k.mean()) - 273.15, 2),
        "frac_days_below_0c": round(float(np.mean(t_k < 273.15)), 3),
        # FREEZE–THAW — a second question of the same series, added 2026-09-24 for FMEA #26
        # (00_07 HW.36): frost-wedging needs water in a pocket to FREEZE, so what matters is not
        # the mean but whether every winter crosses zero, and how often. ⛔ Daily MEANS only: the
        # true crossing count is HIGHER (nights), so every number here is a LOWER bound — and the
        # coldest daily mean sits near the EDLC's -25 °C floor, which no canon line carries.
        "freeze_thaw": _freeze_thaw(rows),
        "t_field_assumed_c": round(t_field_assumed_k - 273.15, 2),
        "by_ea": per_ea,
        "assumed_is_conservative": True,  # asserted per Ea above
        "break_even_ea_ev": {
            f"{target_years:g}_yr_at_{target_weeks}_wk_t_eff": break_even_ea(t_eff),
            f"{target_years:g}_yr_at_{target_weeks}_wk_assumed": break_even_ea(lambda _ea: t_field_assumed_k),
        },
        "ea_foreign_reading": {
            "ea_ev": round(foreign, 4),
            "role": "FOREIGN — Icorr (Tafel), pH 1.5 brine + H2S/CO2 12 MPa, 23-100 °C; not ion release in sap",
            "source": "Sci. Rep. 2022, 12, 16586 (doi 10.1038/s41598-022-21047-0), Fig. 18",
            "years_12_wk_at_t_eff": round(years(foreign, 12, t_eff(foreign)), 2),
        },
        "ceiling": "air ≠ stem and frost ≠ slow liquid both lower the true T_eff → years here are a "
                   "LOWER bound on T; Ea itself has no source for our medium, and the foreign reading "
                   "prices that: an order lower Ea turns the 12-week test into months of field time",
    }
    print(f"  mean {out['mean_c']} °C · days < 0 °C {out['frac_days_below_0c']:.0%} · "
          f"break-even Ea for {target_years:g} yr: {out['break_even_ea_ev']}")
    print(f"  foreign reading Ea {foreign:.3f} eV → 12 wk ≈ {out['ea_foreign_reading']['years_12_wk_at_t_eff']} yr")
    return out


def capacitor_life_hours(
    rated_hours: float,
    t_rated_c: float,
    v_rated_v: float,
    t_field_c: float,
    v_field_v: float,
    *,
    dt_double_c: float,
    dv_double_v: float,
) -> float:
    """HW.37 — vendor EDLC/electrolytic-capacitor endurance-hours doubling rule:

        life(T, V) = rated_hours * 2^((T_rated-T)/dt_double) * 2^((V_rated-V)/dv_double)

    This is the industry "N-rule" vendor app notes cite as an Arrhenius-derived
    approximation (e.g. "life doubles for every dt_double °C drop"), applied as a
    discrete step factor — NOT the continuous fixed-Ea exp() kernel in
    arrhenius_aging() above (see that function's docstring: a fixed-Ea continuous
    Arrhenius over the same 70->10°C span gives a materially different, MORE
    conservative acceleration than a flat "2x per 10°C" applied uniformly — a
    known model-choice distinction, not an error in either model).
    Both steps are REQUIRED: a default step is a silent reading (§Critical Rules #48), and
    the one this kernel used to default to was a voltage step with no primary.
    """
    accel_t = 2.0 ** ((t_rated_c - t_field_c) / dt_double_c)
    accel_v = 2.0 ** ((v_rated_v - v_field_v) / dv_double_v)
    return rated_hours * accel_t * accel_v


HOURS_PER_YEAR = 365.25 * 24.0  # consistent with kirkendall_diffusion()'s 365.25 d/yr below


def fig1_slope_dec_per_c(line) -> float:
    """Decades of life lost per °C along one PS-5006 Figure 1 line, from its two read ends."""
    (t0, h0), (t1, h1) = line
    return (math.log10(h0) - math.log10(h1)) / (t1 - t0)


def fig1_doubling_interval_k() -> float:
    """PS-5006 Figure 1's thermal step: the mean slope of its two 30 % lines — the KR's own end-of-life
    criterion (ΔC 30 %); the 50 % line is printed beside it, never averaged in."""
    s = 0.5 * (fig1_slope_dec_per_c(PS5006_FIG1_30PCT_2V5) + fig1_slope_dec_per_c(PS5006_FIG1_30PCT_1V8))
    return math.log10(2.0) / s


def two_row_dv_per_doubling(dt_double_c: float, rows=EATON_KR_LIFE_ROWS) -> float:
    """The voltage step per doubling, per PART, that carries the anchor Life row exactly onto the other one at a
    given thermal step: dV = (V_A − V_B) / (log2(H_B/H_A) + (T_B − T_A)/dT). Two rows are ONE equation in the two
    steps, so dV is a function of the thermal step, never a number by itself. Both rows are guaranteed minima, so
    at that step this is the WEAKEST voltage effect still honouring row B — any smaller dV honours it too."""
    (h_a, t_a, v_a), (h_b, t_b, v_b) = rows
    return (v_a - v_b) / (math.log2(h_b / h_a) + (t_b - t_a) / dt_double_c)


def eaton_readings() -> dict:
    """The named (thermal step, voltage step) readings of the surviving SKU, each by how it is BUILT
    (in-silico §When Modifying #45): the adverse end is a measured property of the set, not of a name."""
    dt_fig = fig1_doubling_interval_k()
    return {
        "two_row_bound": {
            "dt_double_c": THERMAL_DOUBLING_INTERVAL_K,
            "dv_double_v": two_row_dv_per_doubling(THERMAL_DOUBLING_INTERVAL_K),
            "built_from": "both Life rows of Technical Data 4327 as guaranteed minima + PS-5006's text thermal rule "
                          "(2× per 10 °C) — the SHORTEST life of every (anchor-row life ≥ its rating, voltage step) "
                          "pair that honours both rows under that rule (`bound_control`); a bound only while the true "
                          "thermal step is no SHALLOWER than 10 K, and not a ceiling on any other reading",
        },
        "two_row_fig1_slope": {
            "dt_double_c": dt_fig,
            "dv_double_v": two_row_dv_per_doubling(dt_fig),
            "built_from": "both Life rows + PS-5006 Figure 1's thermal slope (its two 30 % lines); the figure plots "
                          f"nothing below {min(PS5006_FIG1_30PCT_2V5[0][0], PS5006_FIG1_30PCT_1V8[0][0]):.0f} °C, so "
                          "a field life from it is an extrapolation",
        },
        "unsourced_0v4_part": {
            "dt_double_c": THERMAL_DOUBLING_INTERVAL_K,
            "dv_double_v": VOLTAGE_DOUBLING_UNSOURCED_0V4_V,
            "built_from": "0.4 V per part — no primary in the tree; «Eaton's own points» give 0.76 V per part (0.38 V per "
                          "cell) under the text rule, so the attribution does not hold for the part — where the 0.4 V came "
                          "from, nothing in the tree says",
        },
        "unsourced_0v2_part": {
            "dt_double_c": THERMAL_DOUBLING_INTERVAL_K,
            "dv_double_v": VOLTAGE_DOUBLING_UNSOURCED_0V2_V,
            "built_from": "0.2 V per part — no primary in the tree",
        },
    }


def bound_life_hours(t_field_c: float, v_field_v: float, dt_double_c: float = THERMAL_DOUBLING_INTERVAL_K,
                     rows=EATON_KR_LIFE_ROWS) -> float:
    """The two rows' lower bound at (T, V), PIECEWISE: log2 life = log2 L_A·(1 − (V_A − V)/(V_A − V_B)) + const, so
    the minimum over anchor lives L_A ≥ H_A sits at L_A = H_A only while V ≥ V_B. Below row B's voltage the
    coefficient turns negative and the minimum moves to the anchor at which row B needs NO voltage effect: the rows
    give no voltage credit below V_B, and the bound is row B carried by the thermal step alone."""
    (h_a, t_a, v_a), (h_b, t_b, v_b) = rows
    assert v_field_v <= v_a, "above the anchor voltage the bound flips side — not modelled"
    if v_field_v >= v_b:
        return capacitor_life_hours(h_a, t_a, v_a, t_field_c, v_field_v, dt_double_c=dt_double_c,
                                    dv_double_v=two_row_dv_per_doubling(dt_double_c, rows))
    return h_b * 2.0 ** ((t_b - t_field_c) / dt_double_c)


def reading_life_hours(t_field_c: float, v_field_v: float, name: str, r: dict, anchor=EATON_KR_LIFE_ROWS[0]) -> float:
    if name == "two_row_bound":
        return bound_life_hours(t_field_c, v_field_v, r["dt_double_c"])
    return capacitor_life_hours(*anchor, t_field_c, v_field_v, dt_double_c=r["dt_double_c"], dv_double_v=r["dv_double_v"])


def readings_years(t_field_c: float, v_field_v: float, readings: dict | None = None,
                   anchor=EATON_KR_LIFE_ROWS[0]) -> dict:
    """Life in years per named reading at one (temperature, voltage) — the one call `71` makes."""
    readings = eaton_readings() if readings is None else readings
    return {f"{name}_yr": round(reading_life_hours(t_field_c, v_field_v, name, r, anchor) / HOURS_PER_YEAR, 1)
            for name, r in readings.items()}


def vbat_ov_for_years(t_field_c: float, years: float, reading: dict, anchor=EATON_KR_LIFE_ROWS[0],
                      name: str = "") -> float | None:
    """The highest storage voltage at which `reading` still gives `years` at t_field — the derate lever priced.
    Capped at the anchor voltage (the rated voltage already holds). For the BOUND, a voltage below row B's is no
    answer: the bound stops growing there (`bound_life_hours`), so if the closed form lands below V_B no storage
    voltage holds `years` on the bound — None, never a number."""
    h_a, t_a, v_a = anchor
    thermal = 2.0 ** ((t_a - t_field_c) / reading["dt_double_c"])
    need = years * HOURS_PER_YEAR / (h_a * thermal)
    if need <= 1.0:
        return v_a
    v = v_a - reading["dv_double_v"] * math.log2(need)
    if name == "two_row_bound" and v < EATON_KR_LIFE_ROWS[1][2]:
        return None
    return math.floor(v * 1000.0) / 1000.0   # a CEILING: rounded down, never to nearest


def bound_control(t_field_c: float, v_field_v: float) -> dict:
    """A control that CAN fail (§When Modifying #8): over every anchor-row life L_A ≥ its rating (up to well past the
    anchor at which row B needs no voltage effect) and every voltage step, keep the pairs that honour row B under the
    text thermal rule, and find the shortest life at (T, V). It must not land below `bound_life_hours` and must come
    within the grid's resolution of it. A coding error in the closed form, a row order swapped, or a voltage below row
    B's taken by the unpiecewise form (it overstates the bound there) reds here — so it is run across the voltage
    range, not only at the operating point."""
    (h_a, t_a, v_a), (h_b, t_b, v_b) = EATON_KR_LIFE_ROWS
    dt = THERMAL_DOUBLING_INTERVAL_K
    best = math.inf
    l_free = h_b * 2.0 ** ((t_b - t_a) / dt)          # the anchor at which row B needs no voltage effect
    for l_a in np.geomspace(h_a, 2.0 * l_free, 121):
        for dv in np.geomspace(0.05, 500.0, 2001):
            if l_a * 2.0 ** ((t_a - t_b) / dt) * 2.0 ** ((v_a - v_b) / dv) < h_b * (1.0 - 1e-12):
                continue
            best = min(best, capacitor_life_hours(l_a, t_a, v_a, t_field_c, v_field_v, dt_double_c=dt, dv_double_v=dv))
    bound = bound_life_hours(t_field_c, v_field_v)
    assert bound * (1.0 - 1e-9) <= best <= bound * 1.02, (
        f"bound_control: grid minimum {best:.0f} h against the closed-form bound {bound:.0f} h at {t_field_c} °C, {v_field_v} V")
    return {"t_c": t_field_c, "v": round(v_field_v, 3), "grid_min_years": round(best / HOURS_PER_YEAR, 2),
            "closed_form_years": round(bound / HOURS_PER_YEAR, 2)}


def fig1_cell_voltage_check(dt_double_c: float = THERMAL_DOUBLING_INTERVAL_K) -> dict:
    """PS-5006 Figure 1 also prints a CELL voltage effect (30 % at 1.8 V ⊥ at 2.5 V). Carried to the KR part
    (× cells in series) it is a much weaker voltage effect than the rows allow; this asks whether it can be a
    reading of the KR at all: it can only if it honours the KR's row B."""
    (_, h25), (_, h18) = PS5006_FIG1_30PCT_2V5[1], PS5006_FIG1_30PCT_1V8[1]
    assert PS5006_FIG1_30PCT_2V5[1][0] == PS5006_FIG1_30PCT_1V8[1][0], "the two 30 % lines must be read at one T"
    ratio = h18 / h25
    dv_cell = (2.5 - 1.8) / math.log2(ratio)
    dv_part = dv_cell * EATON_KR_CELLS_IN_SERIES
    (h_a, t_a, v_a), (h_b, t_b, v_b) = EATON_KR_LIFE_ROWS
    row_b_pred = capacitor_life_hours(h_a, t_a, v_a, t_b, v_b, dt_double_c=dt_double_c, dv_double_v=dv_part)
    return {
        "life_ratio_1v8_over_2v5_at_70c": round(ratio, 2),
        "dv_double_v_per_cell": round(dv_cell, 2),
        "dv_double_v_per_part": round(dv_part, 2),
        "predicts_row_b_hours": round(row_b_pred),
        "row_b_rated_hours": h_b,
        "admissible_with_rated_anchor": row_b_pred >= h_b,
        "why": "paired with the RATED anchor (row A at exactly its rating) it predicts row B below its guarantee, so it is "
               "not a reading of the KR as that pair; with a free anchor it needs row A to outlive its rating several-fold, "
               "which nothing states (the figure's cells are a 2.5 V generic line, not the KR coin cell)",
    }


def edlc_endurance_hours():
    """HW.37 — EDLC calendar-life via temperature+voltage endurance-hours doubling,
    for both SKUs the canon has weighed (`02_01 §3` поз.3): Eaton KR-5R5H474-R and
    KEMET FG0H474ZF, both rated 1000 h @ 70°C @ 5.5 V (00_07 HW.37).
    ⚖️ 2026-09-22: the KEMET part is GEOMETRICALLY EXCLUDED (H 18.0 mm fits no
    configuration) and the Eaton one is the surviving SKU. Its row STAYS here on
    purpose — the electrical equivalence computed below is precisely WHY geometry
    got to decide, so deleting it would erase the verdict's own ground.
    2026-11-07 (00_07 HW.37): the Eaton row is judged on BOTH Life rows of its datasheet
    (§Critical Rules #48) and on PS-5006 — the voltage step is no longer a pick from an
    unsourced bracket; the vendor-grounded lower bound is `two_row_bound`. KEMET has one
    row and its own coefficient unpublished, so it keeps the two unsourced readings only.
    """
    banner("4. EDLC Endurance-Hours — Temperature + Voltage Doubling (HW.37)")
    readings = eaton_readings()
    unsourced = {k: v for k, v in readings.items() if k.startswith("unsourced_")}
    cell_check = fig1_cell_voltage_check()
    fig1 = {
        "slopes_dec_per_c": {
            "30pct_2v5": round(fig1_slope_dec_per_c(PS5006_FIG1_30PCT_2V5), 4),
            "30pct_1v8": round(fig1_slope_dec_per_c(PS5006_FIG1_30PCT_1V8), 4),
            "50pct_2v5": round(fig1_slope_dec_per_c(PS5006_FIG1_50PCT_2V5), 4),
        },
        "doubling_interval_k": round(fig1_doubling_interval_k(), 2),
        "factor_per_10k": round(2.0 ** (10.0 / fig1_doubling_interval_k()), 2),
        "text_rule_factor_per_10k": round(2.0 ** (10.0 / THERMAL_DOUBLING_INTERVAL_K), 2),
        "cell_voltage_check": cell_check,
    }
    print("  Rule: life ∝ 2^(ΔT/dT) · 2^(ΔV/dV); Eaton's two Life rows fix ONE combination of dT and dV")
    print(f"  PS-5006 thermal step: text {THERMAL_DOUBLING_INTERVAL_K:.0f} K (×{fig1['text_rule_factor_per_10k']}/10 K) "
          f"⊥ Figure 1 {fig1['doubling_interval_k']} K (×{fig1['factor_per_10k']}/10 K)")
    for name, r in readings.items():
        print(f"    {name:<20s} dT {r['dt_double_c']:5.2f} K · dV {r['dv_double_v']:.3f} V/part "
              f"({r['dv_double_v'] / EATON_KR_CELLS_IN_SERIES:.3f} V/cell)")
    print(f"  Figure 1 cell voltage ×{cell_check['life_ratio_1v8_over_2v5_at_70c']} for 2.5→1.8 V → "
          f"{cell_check['dv_double_v_per_part']} V/part; predicts row B {cell_check['predicts_row_b_hours']} h vs "
          f"{cell_check['row_b_rated_hours']:.0f} h rated → admissible with the rated anchor: {cell_check['admissible_with_rated_anchor']}")

    skus = {
        "Eaton_KR-5R5H474-R": ({"rated_hours": EATON_KR_RATED_HOURS, "t_rated_c": EATON_KR_RATED_TEMP_C,
                                "v_rated_v": EATON_KR_RATED_VOLTAGE_V}, readings),
        "KEMET_FG0H474ZF": ({"rated_hours": KEMET_FG_RATED_HOURS, "t_rated_c": KEMET_FG_RATED_TEMP_C,
                             "v_rated_v": KEMET_FG_RATED_VOLTAGE_V}, unsourced),
    }
    results = {}
    for name, (sku, rds) in skus.items():
        anchor = (sku["rated_hours"], sku["t_rated_c"], sku["v_rated_v"])
        print(f"\n  {name}: rated {sku['rated_hours']:.0f} h @ {sku['t_rated_c']:.0f}°C @ {sku['v_rated_v']:.2f} V")
        res = {"rated": dict(sku), "readings": {k: {**v, "dv_double_v": round(v["dv_double_v"], 4),
                                                    "dt_double_c": round(v["dt_double_c"], 3)} for k, v in rds.items()},
               "at_rated_voltage": {}, "voltage_derating": {}}
        # (a) At full rated voltage — temperature-only (PS-5006's text rule), matches the 2026-09-09 hand-calc.
        for t_field in FIELD_TEMPS_C:
            life_h = capacitor_life_hours(*anchor, t_field, sku["v_rated_v"],
                                          dt_double_c=THERMAL_DOUBLING_INTERVAL_K, dv_double_v=1.0)
            res["at_rated_voltage"][str(t_field)] = {"life_hours": round(life_h, 0),
                                                     "life_years": round(life_h / HOURS_PER_YEAR, 2)}
            print(f"    @ {t_field:4.0f} °C, rated V: {life_h:8.0f} h = {life_h / HOURS_PER_YEAR:5.2f} yr")
        # (b) The three pre-verdict VBAT_OV candidates at the coldest reference point — kept because a letter's
        # repo note quotes them; every reading, never a pair.
        t_field = FIELD_TEMPS_C[-1]
        for v_target in (5.37, 5.29, 5.20):
            res["voltage_derating"][str(v_target)] = readings_years(t_field, v_target, rds, anchor)
        # (c) The RATIFIED operating point (VBAT_OV 4.822 V, Derate — founder 2026-09-09), at BOTH reference points,
        # and the VBAT_OV each reading needs for the service life — the lever the derate verdict prices.
        ratified = {"v_target": VBAT_OV_RATIFIED_V}
        for_life = {"years": ANCHOR_SERVICE_LIFE_YEARS}
        for t_f in FIELD_TEMPS_C:
            ratified[str(t_f)] = readings_years(t_f, VBAT_OV_RATIFIED_V, rds, anchor)
            for_life[str(t_f)] = {k: vbat_ov_for_years(t_f, ANCHOR_SERVICE_LIFE_YEARS, r, anchor, k) for k, r in rds.items()}
            print(f"    @ {t_f:4.0f} °C, {VBAT_OV_RATIFIED_V} V: " +
                  " · ".join(f"{k} {v}" for k, v in ratified[str(t_f)].items()))
            print(f"    @ {t_f:4.0f} °C, VBAT_OV for {ANCHOR_SERVICE_LIFE_YEARS:g} yr: " +
                  " · ".join(f"{k} {v} V" for k, v in for_life[str(t_f)].items()))
        res["ratified_vbat_ov"] = ratified
        res["vbat_ov_for_service_life"] = for_life
        if rds is readings:
            res["life_rows"] = [list(r) for r in EATON_KR_LIFE_ROWS]
            res["cells_in_series"] = EATON_KR_CELLS_IN_SERIES
            res["ps5006_fig1"] = fig1
            v_b = EATON_KR_LIFE_ROWS[1][2]
            res["bound_control"] = [bound_control(t, v) for t in FIELD_TEMPS_C
                                    for v in (EATON_KR_RATED_VOLTAGE_V, VBAT_OV_RATIFIED_V, v_b + 0.2, v_b, v_b - 0.3)]
            res["bound_below_row_b_v"] = ("below row B's voltage the rows give no voltage credit: the bound is row B "
                                          "carried by the thermal step alone (`bound_life_hours`)")
        results[name] = res

    print()
    print("  ⚖️  Derate RATIFIED 2026-09-09 (VBAT_OV 4.822 V) and SKU closed 2026-09-22 (Eaton KR); since 2026-11-07")
    print("      the lower bound is the datasheet's own two Life rows under PS-5006's text rule (two_row_bound).")
    return results


def kirkendall_diffusion():
    """Fick's 1st law: V/Al/Nb/Zr diffusion through the passive oxide, PER candidate alloy (Stage-2
    coin bake-off, 01_02 §2.5). Composition-driven: release ∝ bulk wt%, so 4% V gives the 56×
    baseline and every V-free alloy gives ~0. The oxide-diffusion D is a SHARED order-of-magnitude constant,
    labelled literature with NO source named — every release below is linear in it (per-alloy oxide diffusivity is rarely published; the composition effect dominates the small
    Nb/Zr/Ta oxide-stability difference). Output is nested {alloy: {year: {...}}}.
    Nb and Zr (00_07 HW.3, 2026-10-18): the ICP-MS letters ask for both, and without a channel the V-free candidates
    have nothing to calibrate. CAN: give each alloy its Nb and Zr column, linear in its own wt% — a measured release
    then calibrates D/L as m / (C0·t). CANNOT: say how fast Nb or Zr moves — their D is a PLACEHOLDER equal to D(V),
    not a reading that they move like V. No Ti or Ta channel: this models a minor element crossing the base metal's
    oxide, and Ti (or Ta, for the Ta coupon) is the base."""
    banner("2. Kirkendall Ion Diffusion (V/Al/Nb/Zr through the oxide) — per alloy")

    # Diffusion coefficients through the passive oxide — labelled literature, SOURCE NOT NAMED (order of magnitude;
    # shared across Ti alloys, 01_02 §2.5). The release is linear in D, so the magnitude of D is the magnitude of the answer.
    D_V = 1e-20     # m²/s — V through TiO₂ (very slow, dense oxide)
    D_AL = 5e-20    # m²/s — Al through TiO₂ (slightly faster)
    D_NB = D_V      # m²/s — PLACEHOLDER, uncalibrated, no source: set to D(V) only so the column exists
    D_ZR = D_V      # m²/s — PLACEHOLDER, uncalibrated, no source: set to D(V) only so the column exists
    L_OXIDE = 5e-9  # m — passive layer thickness (5 nm)
    A = 2e-4        # m² (2 cm² coin face)
    V_TARGET = 0.02  # µg/cm² — toxicological target (01_02 §2.4)

    years = [1, 5, 10, 20, 40]

    print(f"  D(V) = {D_V:.0e} m²/s, D(Al) = {D_AL:.0e} m²/s, D(Nb) = D(Zr) = {D_NB:.0e} m²/s (placeholder) · "
          f"oxide {L_OXIDE*1e9:.0f} nm · {A*1e4:.0f} cm²")
    print(f"  {'alloy':>20s}  {'V wt%':>6s}  {'Al wt%':>6s}  {'V@20yr':>10s}  {'Al@20yr':>10s}  {'Nb@20yr':>10s}  "
          f"{'Zr@20yr':>10s}  {'V safe':>7s}")
    print(f"  {'-'*92}")

    results = {}
    for alloy, props in ALLOY_PROPERTIES.items():
        rho = props["rho_kg_m3"]
        # Steady-state Fick's 1st law flux: J = D · C0 / L  (C0 = wt-fraction · density), kg/(m²·s)
        flux = {el: d * (props[f"{el}_wt"] / 100 * rho) / L_OXIDE
                for el, d in (("V", D_V), ("Al", D_AL), ("Nb", D_NB), ("Zr", D_ZR))}
        per_year = {}
        for y in years:
            t = y * 365.25 * 86400  # seconds
            m_cm2 = {el: j * A * t * 1e6 / (A * 1e4) for el, j in flux.items()}   # µg/cm²
            # a placeholder D says so in the field's own name, so no reader takes the column for a prediction
            per_year[str(y)] = {**{f"{el}_ug_cm2{'_placeholder_D' if el in ('Nb', 'Zr') else ''}": round(m, 6)
                                   for el, m in m_cm2.items()},
                                "V_safe": m_cm2["V"] < V_TARGET}
        r20 = per_year["20"]
        ok = "✅" if r20["V_safe"] else "❌"
        print(f"  {alloy:>20s}  {props['V_wt']:>6.1f}  {props['Al_wt']:>6.1f}  {r20['V_ug_cm2']:>8.3f}µg  "
              f"{r20['Al_ug_cm2']:>8.3f}µg  {r20['Nb_ug_cm2_placeholder_D']:>8.3f}µg  {r20['Zr_ug_cm2_placeholder_D']:>8.3f}µg  {ok:>7s}")
        results[alloy] = per_year

    print()
    print("  Composition dominates: V-free alloys release ZERO V (the 56× toxicity driver gone);")
    print("  Al-bearing (4V, 7Nb) still leak Al (phytotoxic in acidic sap, 01_04 §4.2 tree-lens).")
    return results


def press_fit_window():
    """H7/s6 interference window with ΔCTE for Ti↔PEEK."""
    banner("3. H7/s6 Press-Fit Interference Window")

    # Material props from lib.constants (One-Home, HW.3.IS); ΔCTE drives the temperature term below.
    ALPHA_TI = ALLOY_PROPERTIES["Ti-6Al-4V"]["alpha_1K"]   # 1/K
    ALPHA_PEEK = ALPHA_PEEK_1K   # 1/K

    # Shaft Ø from the interface radius (lib.constants, One-Home) — a local `D_SHAFT = 11.0` stood here in a
    # file that already imports the same Ø as R_INTERFACE_M.
    D_SHAFT = 2.0 * R_INTERFACE_M * 1000.0   # mm

    T_ASSEMBLY = T_ASSEMBLY_C   # °C (lib.constants)
    T_RANGE = [-30, -10, 0, 20, 40]

    # Interference band (diametral µm) — READ from lib.constants, never re-typed. ⛔ A local copy of the
    # ISO 286 deviations stood here, and it repeated the table read that constants.py flags: +23/+34 is the
    # r6 row, so the band is H7/r6 under an H7/s6 label (s6 on Ø11 gives 10–39). No table class is
    # ratified — the band is to be solved from the Lamé window (00_07 HW.3, ⚖️ 2026-09-18), and 5-34's MIN
    # lies below its floor; until the window's inputs land the band stays the tree's working input,
    # labelled as such.
    I_MIN = H7S6_INTERF_DIA_MIN_UM   # governs the window floor
    I_MAX = H7S6_INTERF_DIA_MAX_UM   # governs hoop

    print(f"  Shaft: ∅{D_SHAFT:.0f} mm — band labelled H7/s6, read from the r6 row (no table class ratified — the")
    print("  band is to be solved from the Lamé window, HW.3 2026-09-18; 5-34's MIN lies below its floor)")
    print(f"  Interference: {I_MIN:.0f}–{I_MAX:.0f} µm diametral")
    print(f"  ΔCTE: {(ALPHA_PEEK - ALPHA_TI)*1e6:.1f}×10⁻⁶ /K")
    print()

    print(f"  {'T (°C)':>8s}  {'ΔCTE (µm)':>10s}  {'Eff. min I':>12s}  {'Eff. max I':>12s}  {'σ_hoop':>10s}  "
          f"{'hoop':>5s}  {'grip@min':>8s}")
    print(f"  {'-'*72}")

    results = {}
    for T in T_RANGE:
        dT = T - T_ASSEMBLY
        # PEEK shrinks more than Ti when cooling → interference increases
        # PEEK expands more than Ti when heating → interference decreases
        delta_I = (ALPHA_PEEK - ALPHA_TI) * dT * D_SHAFT * 1000  # µm

        eff_min = I_MIN - delta_I
        eff_max = I_MAX - delta_I

        # Hoop stress from max effective interference — consistent thick-wall Lamé (lib.mechanics, HW.3.IS
        # 2026-06-22; was a thin-wall E·δ/D·2 approx that over-stated ~2×). eff_max is DIAMETRAL → radial = /2.
        sigma_max = thick_wall_hoop(eff_max * 1e-6 / 2.0, R_INTERFACE_M, R_OUTER_M, E_PEEK_PA, NU_PEEK)["sigma_t"]
        # ⛔ TWO mechanisms, two flags. A single `safe` stood here and judged the hoop stress at the band's
        # MAX only, so +40 °C read «safe» while the band's MIN had already opened to a clearance.
        hoop_ok = bool(abs(sigma_max) < SIGMA_YIELD_PEEK_PA)
        grip_at_min = bool(eff_min > 0.0)

        print(f"  {T:>8.0f}  {delta_I:>+10.1f}  {eff_min:>12.1f}  {eff_max:>12.1f}  {sigma_max/1e6:>8.1f} MPa  "
              f"{'✅' if hoop_ok else '❌':>5s}  {'✅' if grip_at_min else '❌ gap':>8s}")

        results[str(T)] = {
            "delta_I_um": round(delta_I, 2),
            "eff_min_um": round(eff_min, 2),
            "eff_max_um": round(eff_max, 2),
            "sigma_hoop_MPa": round(sigma_max / 1e6, 2),
            "hoop_below_peek_yield": hoop_ok,
            "interference_retained_at_band_min": grip_at_min,
        }

    # ⛔ DERIVED, never typed: «safe across −30 to +40 °C» was a printed constant beside a row that said
    #    otherwise one line up.
    opens = [t for t, r in results.items() if not r["interference_retained_at_band_min"]]
    print()
    print(f"  {'✅' if all(r['hoop_below_peek_yield'] for r in results.values()) else '❌'} hoop stress "
          f"{'below' if all(r['hoop_below_peek_yield'] for r in results.values()) else 'ABOVE'} PEEK yield "
          "over the whole range (the band MAX governs it)")
    print(f"  {'⚠️ the band MIN opens to a CLEARANCE at ' + ', '.join(f'{t} °C' for t in opens) + ' (below the window floor, 00_07 HW.3)' if opens else '✅ the band MIN keeps interference everywhere'}"
          " — the Ti<->PEEK path is not sealed by design (00_07 HW.34)")

    return results


def main() -> int:
    arrhenius = arrhenius_aging()
    field_t = arrhenius_field_temperature()
    kirkendall = kirkendall_diffusion()
    press_fit = press_fit_window()
    edlc_endurance = edlc_endurance_hours()

    output = {
        "arrhenius_aging": arrhenius,
        "arrhenius_field_temperature": field_t,
        "kirkendall_diffusion": kirkendall,
        "press_fit_H7s6": press_fit,
        "edlc_endurance_hours": edlc_endurance,
    }

    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
