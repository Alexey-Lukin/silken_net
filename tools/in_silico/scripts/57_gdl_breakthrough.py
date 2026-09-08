#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.25 — PTFE-GDL cathode membrane: liquid-entry (breakthrough) pressure and the O2 budget.

WHY THIS EXISTS. `01_04 §5.3` specifies the Zone-3 gas-diffusion membrane by pore size
(0.2-1.0 um), thickness (20-100 um) and contact angle (>110 deg), and justifies BOTH ends of the
pore window in prose: "not larger than 15 um -> water breakthrough", "not smaller than 0.02 um ->
O2 diffusion chokes". `01_04 §5.6` then prescribes a bench test — a 30 cm water column, with an
acceptance criterion of ">= 1 m H2O". None of those four numbers was ever computed, and two of
them sit in the same line without a stated relation. This script closes the desk half with the
two closed forms that govern the membrane, so the bench is built to answer a question rather
than to confirm a guess.

  (1) LIQUID ENTRY / BREAKTHROUGH — Young-Laplace in a cylindrical pore:
          dP = -4 * gamma * cos(theta) / d
      For a hydrophobic pore (theta > 90 deg) cos(theta) < 0, so dP > 0 is the over-pressure
      that forces water in. Reported in Pa and in metres of water head, which is the unit the
      bench actually builds.

  (2) O2 SUPPLY — steady Fickian diffusion through the porous membrane with a Bosanquet
      (bulk + Knudsen) diffusivity, compared against the O2 the cathode consumes at the
      literature peak current density (lib.constants J_MAX_25C, 4 electrons per O2).

BOTH are closed-form: no fitted parameters, no simulation. That is the point — the numbers are
auditable by hand from the inputs printed below.

DECLARED CEILINGS:
  * A real membrane is a pore-size DISTRIBUTION with a tail; every number here is for a NOMINAL
    cylindrical pore. The largest as-made pore (and any pinhole) governs the real part, which is
    exactly what a bench measurement adds and a calculation cannot.
  * Cylindrical-pore Young-Laplace ignores pore tortuosity, non-circular cross-sections and any
    surface roughness (Cassie/Wenzel) correction — all of which shift LEP, mostly downward.
  * 🔴 CONTACT ANGLE IS THE WHOLE ANSWER, and the canon carries two different values for it —
    the §5.3 table guarantees only ">110 deg" while §5.2 prose says "~110-120". Every inverted
    number below therefore has a theta SLICE attached, and quoting one without it is how the
    document's own "no pores > 15 um" came to look like an error: at 120 deg the same criterion
    gives 14.87 um, i.e. that threshold IS this calculation taken at the best-case angle. The
    correction is not "15 was wrong" but "15 assumed the top of the range while the spec
    guarantees the bottom".
  * Theta is also the axis the design is most exposed on, and this document is about RESIN:
    resin acids and terpenes are surfactants, so both gamma and theta degrade in service. The
    theta at which each pore size loses its margin against the worst field load is computed
    below and is the acceptance criterion the 12-week rain/dew test actually needs.
  * The O2 side assumes a DRY, open membrane. Partial wetting, condensation or dust blinding
    reduce the open porosity and are NOT modelled; they are the realistic failure mode.
  * The field loads are HAND-SET (four scenarios, no field data). Any conclusion of the form
    "X is not the risk" is arithmetic against those four numbers, not a measurement of the site.
    Droplet impact (water hammer), which can exceed a static head by orders of magnitude, is not
    among them.
  * `J_MAX_25C` in lib.constants is the ANODE pair's literature current density (Zafar 2012).
    Using it as the cathode's demand is legitimate only because the cell is in series and the
    current is shared — it is not an independent cathode measurement.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import A_ELECTRODE, F_CONST, J_MAX_25C, KINETICS_DIR, R_GAS, REPO_ROOT, TEMPERATURE_K
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "gdl_breakthrough.json"

# ── Liquid properties (water at 20 C — the install/rain temperature, not the 25 C MD reference) ──
GAMMA_WATER = 0.0728         # N/m — surface tension of water at 20 C (CRC)
RHO_WATER = 998.2            # kg/m3 at 20 C
G_ACCEL = 9.80665            # m/s2 — standard gravity

# ── Canon spec (01_04 §5.3) — mirrors, the home is the doc ──
PORE_SPEC_UM = (0.2, 0.5, 1.0)          # specified pore-size window (0.5 = midpoint, informational)
THICKNESS_SPEC_UM = (20.0, 50.0, 100.0)
CONTACT_ANGLE_DEG = (110.0, 115.0, 120.0)   # §5.3 table ">110"; §5.2 prose "~110-120"
CANON_UPPER_PORE_UM = 15.0              # §5.3 prose "why not pores > 15 um"
CANON_LOWER_PORE_UM = 0.02              # §5.3 prose "why not pores < 0.02 um"
BENCH_COLUMN_M = 0.30                   # §5.6 apparatus as written
BENCH_ACCEPT_M = 1.0                    # §5.6 acceptance criterion in the same line

# ── Gas properties for the O2 half ──
D_O2_AIR = 2.0e-5            # m2/s — O2 in air at ~293 K, 1 atm (CRC)
M_O2 = 0.032                 # kg/mol
X_O2_AIR = 0.2095            # mole fraction of O2 in dry air
P_ATM = 101325.0             # Pa
POROSITY_GDL = 0.5           # open porosity of e-PTFE (typical 0.4-0.8) — swept below
TORTUOSITY_GDL = 2.0         # typical for a stretched-node PTFE web
N_E_PER_O2 = 4               # ORR: O2 + 4H+ + 4e- -> 2H2O (01_04 §5.1)


def liquid_entry_pressure(pore_d_um: float, theta_deg: float, gamma: float = GAMMA_WATER) -> float:
    """Young-Laplace breakthrough over-pressure (Pa) for a cylindrical pore of diameter d."""
    return -4.0 * gamma * math.cos(math.radians(theta_deg)) / (pore_d_um * 1e-6)


def pa_to_m_h2o(p_pa: float) -> float:
    return p_pa / (RHO_WATER * G_ACCEL)


def m_h2o_to_pa(h_m: float) -> float:
    return h_m * RHO_WATER * G_ACCEL


def pore_for_head(head_m: float, theta_deg: float, gamma: float = GAMMA_WATER) -> float:
    """Inverse of Young-Laplace: the largest pore (um) that still holds a given water head."""
    return -4.0 * gamma * math.cos(math.radians(theta_deg)) / m_h2o_to_pa(head_m) * 1e6


def knudsen_diffusivity(pore_d_um: float, t_k: float = TEMPERATURE_K) -> float:
    """D_K = (d/3) * sqrt(8 R T / (pi M))  [m2/s] — free-molecular contribution."""
    return (pore_d_um * 1e-6 / 3.0) * math.sqrt(8.0 * R_GAS * t_k / (math.pi * M_O2))


def effective_diffusivity(pore_d_um: float, porosity: float, tortuosity: float) -> dict:
    """Bosanquet combination of bulk and Knudsen, corrected for the porous path."""
    d_k = knudsen_diffusivity(pore_d_um)
    d_comb = 1.0 / (1.0 / D_O2_AIR + 1.0 / d_k)
    return {"D_knudsen": d_k, "D_bosanquet": d_comb, "D_eff": d_comb * porosity / tortuosity}


def main() -> int:
    banner("HW.25 — PTFE-GDL breakthrough pressure and O2 budget (closed form)")
    print(f"  water: gamma {GAMMA_WATER:.4f} N/m, rho {RHO_WATER:.1f} kg/m3 at 20 C; "
          f"1 m H2O = {m_h2o_to_pa(1.0):.0f} Pa")
    print(f"  spec (01_04 §5.3): pores {PORE_SPEC_UM[0]}-{PORE_SPEC_UM[-1]} um, "
          f"thickness {THICKNESS_SPEC_UM[0]:.0f}-{THICKNESS_SPEC_UM[-1]:.0f} um, "
          f"contact angle > {CONTACT_ANGLE_DEG[0]:.0f} deg")

    # ── (1) breakthrough pressure over the spec window ──────────────────────
    banner("(1) Liquid-entry pressure of the specified pore window")
    print(f"  {'pore (um)':>10s} " + " ".join(f"{'CA ' + str(int(t)) + ' deg':>18s}"
                                              for t in CONTACT_ANGLE_DEG))
    print(f"  {'-' * (11 + 19 * len(CONTACT_ANGLE_DEG))}")
    lep = {}
    for d in PORE_SPEC_UM:
        row = {}
        cells = []
        for th in CONTACT_ANGLE_DEG:
            p = liquid_entry_pressure(d, th)
            row[f"CA_{int(th)}"] = {"pressure_Pa": p, "head_m_H2O": pa_to_m_h2o(p)}
            cells.append(f"{p / 1000:8.1f} kPa /{pa_to_m_h2o(p):5.1f} m")
        lep[f"{d}um"] = row
        print(f"  {d:>10.1f} " + " ".join(f"{c:>18s}" for c in cells))
    worst = liquid_entry_pressure(PORE_SPEC_UM[-1], CONTACT_ANGLE_DEG[0])
    margin = pa_to_m_h2o(worst) / BENCH_ACCEPT_M
    print(f"\n  Worst case in the spec (largest pore {PORE_SPEC_UM[-1]} um at the minimum "
          f"{CONTACT_ANGLE_DEG[0]:.0f} deg): {worst / 1000:.1f} kPa = "
          f"{pa_to_m_h2o(worst):.1f} m H2O")
    best = liquid_entry_pressure(PORE_SPEC_UM[0], CONTACT_ANGLE_DEG[-1])
    print(f"  Best case (smallest pore at {CONTACT_ANGLE_DEG[-1]:.0f} deg): "
          f"{best / 1000:.1f} kPa = {pa_to_m_h2o(best):.1f} m H2O")
    print(f"  => the specified window clears the §5.6 acceptance bar of {BENCH_ACCEPT_M:.0f} m by "
          f"{margin:.0f}x (worst) to {pa_to_m_h2o(best) / BENCH_ACCEPT_M:.0f}x (best).")

    # ── (2) what the prescribed bench can and cannot see ────────────────────
    banner("(2) Inverting the bench: what a water column actually tests")
    d_at_bench = pore_for_head(BENCH_COLUMN_M, CONTACT_ANGLE_DEG[0])
    d_at_accept = pore_for_head(BENCH_ACCEPT_M, CONTACT_ANGLE_DEG[0])
    d_at_spec = pa_to_m_h2o(liquid_entry_pressure(PORE_SPEC_UM[-1], CONTACT_ANGLE_DEG[0]))
    print(f"  §5.6 apparatus  — {BENCH_COLUMN_M * 100:.0f} cm column  -> fails only pores wider than "
          f"{d_at_bench:.1f} um")
    print(f"  §5.6 acceptance — {BENCH_ACCEPT_M:.0f} m column     -> fails only pores wider than "
          f"{d_at_accept:.1f} um")
    print("\n  The same inversion across the canon's OWN theta range — this is the whole story of")
    print(f"  the '{CANON_UPPER_PORE_UM:.0f} um' threshold, and it is not an arithmetic error:")
    theta_inv = {}
    for th in CONTACT_ANGLE_DEG:
        d_acc = pore_for_head(BENCH_ACCEPT_M, th)
        theta_inv[f"CA_{int(th)}"] = {"pore_demanded_um": d_acc,
                                      "vs_canon_prose_x": CANON_UPPER_PORE_UM / d_acc}
        flag = " <- the canon's 15 um" if abs(d_acc - CANON_UPPER_PORE_UM) < 0.5 else ""
        print(f"    theta {th:.0f} deg -> the {BENCH_ACCEPT_M:.0f} m criterion demands "
              f"<= {d_acc:5.2f} um{flag}")
    print(f"  => '{CANON_UPPER_PORE_UM:.0f} um' is this calculation at the TOP of the prose range, "
          f"while the §5.3 table")
    print(f"     guarantees only the BOTTOM ({CONTACT_ANGLE_DEG[0]:.0f} deg), which demands "
          f"<= {d_at_accept:.1f} um. The defect is a")
    print("     theta slice left unstated, not a wrong number.")
    print(f"  To CHALLENGE the widest specified pore ({PORE_SPEC_UM[-1]} um) a water column would "
          f"have to be {d_at_spec:.0f} m tall.")
    print("  => the water column is a GROSS-DEFECT detector (pinholes, lamination damage, a torn")
    print("     web), not a verifier of the pore spec. Verifying the spec needs a PRESSURISED")
    print("     bubble-point rig, which the canon already prescribes for sterilisation QC (§6.3 F5).")
    bubble = {f"{d}um": {"pressure_kPa": liquid_entry_pressure(d, CONTACT_ANGLE_DEG[0]) / 1000.0}
              for d in PORE_SPEC_UM}
    print(f"  Bubble-point pressures to test the spec at CA {CONTACT_ANGLE_DEG[0]:.0f} deg: "
          + " · ".join(f"{d} um -> {bubble[f'{d}um']['pressure_kPa']:.0f} kPa" for d in PORE_SPEC_UM))

    # ── (3) the field demand the membrane actually faces ────────────────────
    banner("(3) The pressure the field actually applies")
    field = {
        "dew_film_1mm": m_h2o_to_pa(0.001),
        "standing_droplet_5mm": m_h2o_to_pa(0.005),
        "driven_rain_wind_20ms_stagnation": 0.5 * 1.2 * 20.0 ** 2,
        "submersion_50mm": m_h2o_to_pa(0.050),
    }
    for k, v in field.items():
        print(f"  {k:<36s} {v:>10.1f} Pa   ({worst / v:,.0f}x below the worst-case LEP)")
    worst_field = max(field.values())
    worst_field_name = max(field, key=field.get)
    print(f"  ⚠️ These four are HAND-SET, not measured, and the upper bound {worst_field:.0f} Pa is "
          f"{worst_field_name},")
    print("     not the wind-driven rain. Droplet impact (water hammer) is not among them.")
    print("  => against THESE loads the nominal pore is not the limit by 2-3 orders of magnitude.")
    print("     That is an elimination, not a positive finding: what remains — a defect in the web")
    print("     or seam, and loss of hydrophobicity — is not computed by the LEP formula at all.")

    # The axis that actually threatens the margin, and it is the one this DOCUMENT is about.
    banner("(3b) How far can the contact angle degrade before the margin closes?")
    print("  Resin acids and terpenes are surfactants: in service both gamma and theta fall. LEP")
    print("  scales with |cos(theta)|, which collapses as theta -> 90 deg, so this is the design's")
    print(f"  real exposure. Theta at which LEP drops to the worst field load ({worst_field:.0f} Pa):")
    theta_fail = {}
    for d in PORE_SPEC_UM:
        # |cos(theta)| = dP * d / (4 gamma)
        c = worst_field * (d * 1e-6) / (4.0 * GAMMA_WATER)
        th = math.degrees(math.acos(-min(c, 1.0)))
        theta_fail[f"{d}um"] = th
        print(f"    pore {d} um -> breaks through only once theta falls to {th:.2f} deg "
              f"(spec floor is {CONTACT_ANGLE_DEG[0]:.0f} deg)")
    print("  => the membrane tolerates a very large loss of hydrophobicity before water enters,")
    print("     which turns the 12-week rain/dew test into a THETA measurement with a number to")
    print("     accept against, instead of a pass/fail with no criterion.")

    # ── (4) O2 supply margin across the whole pore window ───────────────────
    banner("(4) O2 supply through the membrane vs the cathode's demand")
    j_a_m2 = J_MAX_25C * 1e4                      # A/cm2 -> A/m2
    demand = j_a_m2 / (N_E_PER_O2 * F_CONST)      # mol O2 / m2 / s
    c_o2 = X_O2_AIR * P_ATM / (R_GAS * TEMPERATURE_K)
    print(f"  peak current density {J_MAX_25C * 1e6:.0f} uA/cm2 (lib.constants J_MAX_25C, "
          f"electrode {A_ELECTRODE:.1f} cm2) -> O2 demand {demand:.3e} mol/m2/s")
    print(f"  air-side O2 concentration {c_o2:.2f} mol/m3 at {TEMPERATURE_K:.2f} K")
    print(f"\n  {'pore (um)':>10s} {'D_Knudsen':>12s} {'D_Bosanquet':>13s} {'D_eff':>11s} "
          f"{'flux @50um':>13s} {'margin':>10s}")
    print(f"  {'-' * 76}")
    o2 = {}
    for d in (CANON_LOWER_PORE_UM, *PORE_SPEC_UM, CANON_UPPER_PORE_UM):
        dd = effective_diffusivity(d, POROSITY_GDL, TORTUOSITY_GDL)
        flux = dd["D_eff"] * c_o2 / (THICKNESS_SPEC_UM[1] * 1e-6)
        o2[f"{d}um"] = {**dd, "flux_mol_m2_s": flux, "margin_x": flux / demand}
        print(f"  {d:>10.2f} {dd['D_knudsen']:>12.2e} {dd['D_bosanquet']:>13.2e} "
              f"{dd['D_eff']:>11.2e} {flux:>13.2e} {flux / demand:>9,.0f}x")
    thin = effective_diffusivity(PORE_SPEC_UM[0], POROSITY_GDL, TORTUOSITY_GDL)
    thick_flux = thin["D_eff"] * c_o2 / (THICKNESS_SPEC_UM[-1] * 1e-6)
    print(f"\n  Thickest spec membrane ({THICKNESS_SPEC_UM[-1]:.0f} um) at the smallest spec pore "
          f"({PORE_SPEC_UM[0]} um): margin {thick_flux / demand:,.0f}x")
    lower = o2[f"{CANON_LOWER_PORE_UM}um"]
    print(f"  Even at the canon's stated lower bound {CANON_LOWER_PORE_UM} um the margin is "
          f"{lower['margin_x']:,.0f}x — so the diffusion-choke rationale for that bound is NOT")
    print("  supported by transport alone. It may still be right for wetting/manufacturing reasons;")
    print("  this calculation simply does not carry it, and the canon should not claim it does.")

    # ── verdict ─────────────────────────────────────────────────────────────
    banner("Verdict")
    v = [
        f"1. The specified pore window holds {pa_to_m_h2o(worst):.0f}-{pa_to_m_h2o(best):.0f} m of "
        f"water head against hand-set field loads of {min(field.values()):.0f}-"
        f"{max(field.values()):.0f} Pa. Against THOSE loads the nominal pore is not the limit; "
        f"what remains — a web/seam defect, and loss of hydrophobicity — this formula does not "
        f"compute.",
        f"2. The prescribed {BENCH_COLUMN_M * 100:.0f} cm column only fails pores wider than "
        f"{d_at_bench:.0f} um, so it is a gross-defect detector. Keep it as such, and verify the "
        f"pore spec with the bubble-point rig the sterilisation QC already needs "
        f"({bubble[f'{PORE_SPEC_UM[-1]}um']['pressure_kPa']:.0f} kPa for the widest spec pore).",
        f"3. The §5.3 prose bound 'no pores > {CANON_UPPER_PORE_UM:.0f} um' is NOT an arithmetic "
        f"error: it is this same inversion at {CONTACT_ANGLE_DEG[-1]:.0f} deg "
        f"({theta_inv[f'CA_{int(CONTACT_ANGLE_DEG[-1])}']['pore_demanded_um']:.2f} um). What is "
        f"missing is the slice — the §5.3 TABLE guarantees only {CONTACT_ANGLE_DEG[0]:.0f} deg, "
        f"which demands <= {d_at_accept:.1f} um. State theta with the number or neither means "
        f"anything.",
        f"4. The design's real exposure is theta, not pore size: the worst hand-set field load "
        f"breaks through only once the contact angle falls to "
        f"{min(theta_fail.values()):.2f}-{max(theta_fail.values()):.2f} deg. That is the "
        f"acceptance number the 12-week rain/dew test has been missing.",
        f"5. O2 transport exceeds the cathode's peak demand by "
        f"{min(x['margin_x'] for x in o2.values()):,.0f}x at the worst pore in the whole "
        f"0.02-15 um range, so if the cathode is O2-limited the bottleneck is the catalytic "
        f"layer, not the GDL. (The demand uses the anode pair's literature current density — "
        f"legitimate only because the cell is in series.)",
    ]
    for line in v:
        print("  " + line)

    out = {
        "method": "Closed-form Young-Laplace liquid-entry pressure for a cylindrical pore plus a "
                  "Bosanquet (bulk+Knudsen) steady-diffusion O2 budget. No fitted parameters.",
        "inputs": {"gamma_water_N_m": GAMMA_WATER, "rho_water_kg_m3": RHO_WATER,
                   "g_m_s2": G_ACCEL, "temperature_K": TEMPERATURE_K,
                   "pore_spec_um": list(PORE_SPEC_UM),
                   "thickness_spec_um": list(THICKNESS_SPEC_UM),
                   "contact_angle_deg": list(CONTACT_ANGLE_DEG),
                   "porosity": POROSITY_GDL, "tortuosity": TORTUOSITY_GDL,
                   "D_O2_air_m2_s": D_O2_AIR, "j_max_A_cm2": J_MAX_25C,
                   "electrons_per_O2": N_E_PER_O2},
        "liquid_entry_pressure": lep,
        "worst_case_spec": {"pore_um": PORE_SPEC_UM[-1], "contact_angle_deg": CONTACT_ANGLE_DEG[0],
                            "pressure_Pa": worst, "head_m_H2O": pa_to_m_h2o(worst),
                            "margin_vs_acceptance_x": margin},
        "bench_inversion": {
            "apparatus_column_m": BENCH_COLUMN_M,
            "acceptance_column_m": BENCH_ACCEPT_M,
            "pore_failed_by_apparatus_um": d_at_bench,
            "pore_demanded_by_acceptance_um": d_at_accept,
            "canon_prose_upper_pore_um": CANON_UPPER_PORE_UM,
            "canon_prose_optimism_x": CANON_UPPER_PORE_UM / d_at_accept,
            "column_height_to_challenge_widest_spec_pore_m": d_at_spec,
            "bubble_point_kPa": bubble,
        },
        "field_pressures_Pa": field,
        "field_pressure_note": "hand-set scenarios, not site data; the upper bound is "
                               "submersion_50mm, not the wind-driven rain; droplet impact "
                               "(water hammer) is not modelled",
        "theta_inversion": theta_inv,
        "theta_at_which_worst_field_load_breaks_through_deg": theta_fail,
        "o2_budget": {"demand_mol_m2_s": demand, "air_c_O2_mol_m3": c_o2, "per_pore": o2,
                      "margin_thickest_membrane_smallest_SPEC_pore_x": thick_flux / demand,
                      "j_max_provenance": "lib.constants J_MAX_25C is the ANODE pair's literature "
                                          "current density; used here as the cathode demand only "
                                          "because the cell is in series"},
        "verdict": " ".join(v),
        "ceilings": "Nominal cylindrical pores — a real web is a distribution with a tail, and the "
                    "largest as-made pore governs; no Cassie/Wenzel roughness correction; contact "
                    "angle is the spec claim, not our measurement; the O2 half assumes a dry, open "
                    "membrane (wetting, condensation and dust blinding are the real failure mode "
                    "and are not modelled).",
    }
    OUT_JSON.write_text(json.dumps(out, indent=2))
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")

    # Sanity gate: the spec must clear its own acceptance bar, and the bench must be shown to be
    # unable to challenge the spec — the two claims this script exists to establish.
    ok = margin > 1.0 and d_at_bench > PORE_SPEC_UM[-1]
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
