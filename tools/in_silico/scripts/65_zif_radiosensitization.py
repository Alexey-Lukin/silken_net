#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.22 — does the ZIF nanozyme RADIOSENSITISE the enzyme stack under Co-60 gamma? Desk verdict.

`01_04 §6.2` carries an open blocker on the low-dose gamma row: "ZIF may make radiation damage WORSE
(Ce/Co/Cu are radiosensitisers) — check; if so → aseptic enzyme loading AFTER sterilisation". That is
an ARCHITECTURE question, not a detail: it decides whether Гілка A of the split-cycle sterilises the
LOADED anchor (as `§6.3` specifies today) or whether the enzymes must be loaded in a clean laminar
after the Co-60 pass, which is a different factory flow.

The caveat imports a real effect from radiotherapy — high-Z nanoparticle dose enhancement, DEF 1.2-3×
for Au/Gd/Hf at kilovoltage. This script asks whether that effect can exist AT ALL at Co-60's 1.25 MeV,
and answers with transport physics rather than a lab slot. Two INDEPENDENT grounds (Q1, Q2), either of
which alone would settle it, plus a falsification margin (Q3) and the contrast that explains where the
caveat came from (Q4).

  Q1  ENERGY DEPOSITION IS NOT LOCAL HERE. At 1.25 MeV the interaction is Compton, and the secondary
      electron carries a computable mean energy away. If its range is >> the layer thickness, the layer
      is a Bragg-Gray cavity: its dose is set by the electron fluence arriving from the SURROUNDING
      medium, so no local excess of photon interactions can raise it. This is exactly why kV works and
      MV does not — at 50 keV the photoelectron range is a few tens of micrometres, i.e. the scale of
      the structure you are trying to damage.
  Q2  EVEN UNDER FULL EQUILIBRIUM THE COEFFICIENT GOES THE WRONG WAY. Per unit MASS, Compton scales
      with electron density = <Z/A>·N_A, and <Z/A> FALLS with atomic number (0.555 for water, ~0.41 for
      Ce). So a heavy-metal framework absorbs LESS energy per gram, not more.
  Q3  HOW WRONG WOULD Q2 HAVE TO BE. The photoelectric and pair channels are Z-dependent and are not
      computed here. Instead of asserting they are small, the script inverts the question: what share
      of the total mass energy-absorption would a non-Compton channel have to supply in the ZIF, and
      supply in water, for DEF to reach 1.0? That single number is what a lab check would have to beat,
      and it is the honest output of a desk pass.

⚠️ WHAT THIS DOES NOT SETTLE, stated up front because the caveat has a second half hiding inside it.
   "Radiosensitiser" in the literature covers TWO mechanisms and they are unrelated: (a) physical dose
   enhancement — settled here; (b) CHEMICAL amplification of radiolysis, where a redox-active metal
   (Ce III/IV, Cu I/II, Co II/III) turns radiolytic H2O2 into hydroxyl radicals by a Fenton-like route.
   (b) is not a dose effect and no photon-transport argument touches it. It is also NOT symmetric: the
   same nanozyme is chosen for SOD/catalase-like activity (`01_03 §2.2`), so it may as easily scavenge
   the radicals as make them. The desk verdict therefore closes the ARCHITECTURE question and leaves a
   CHEMICAL residual that the already-planned Гілка A activity assay measures directly.

Genre = `53_oxide_det_per_alloy`: literature constants + closed form, answering a lab-gated risk before
the lab. No DFT, no MD. Runs in milliseconds.

Literature anchors (all classic, all closed form — no table lookup):
  · Klein-Nishina differential cross-section — Klein & Nishina, Z. Phys. 52 (1929) 853. Integrated
    numerically here for the mean energy transfer; see the guard in that function for why.
  · Katz-Penfold empirical CSDA range for electrons 0.01-3 MeV: R [g/cm2] = 0.412 * E^(1.265 - 0.0954*ln E)
    — Katz & Penfold, Rev. Mod. Phys. 24 (1952) 28. Used for BOTH the MeV Compton electron and the keV
    photoelectron, so the kV/MV contrast comes from one formula, not two sources.
  · Atomic masses: IUPAC standard atomic weights.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DELTA_MEMBRANE, KINETICS_DIR, REPO_ROOT
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "zif_radiosensitization.json"

E_GAMMA_MEV = 1.25          # Co-60 average of the 1.173/1.332 MeV pair (`01_04 §6.2` dose row)
E_KV_REF_KEV = 50.0         # a representative kV therapy/imaging photon — the regime the caveat comes from
M_E_MEV = 0.51099895        # electron rest energy

# Atomic number and IUPAC standard atomic weight for every element the stack contains.
ELEMENTS = {
    "H": (1, 1.008), "C": (6, 12.011), "N": (7, 14.007), "O": (8, 15.999),
    "S": (16, 32.06), "Co": (27, 58.933), "Cu": (29, 63.546), "Zn": (30, 65.38),
    "Ce": (58, 140.116), "Ti": (22, 47.867),
}

# Materials as ATOM COUNTS, not mass fractions — the framework stoichiometry is what canon gives.
# ZIF-8 node = M(2-methylimidazolate)2 = M·C8H10N4 (`01_03 §2.2`). Canon names the nanozyme
# `nCoCuCeZIF` / `nCuCeAuZIF` but does NOT fix the node stoichiometry, so instead of inventing one the
# sweep brackets it: each pure-metal node is computed, and the all-Ce node is the physical UPPER BOUND
# on <Z> for anything canon could mean. A bound needs no stoichiometry to be true.
MATERIALS = {
    "water (dose reference)": {"H": 2.0, "O": 1.0},
    "protein (laccase, avg. residue)": {"C": 5.0, "H": 8.0, "N": 1.4, "O": 1.6, "S": 0.03},
    "MWCNT support": {"C": 1.0},
    "ZIF-8 (Zn node, parent framework)": {"Zn": 1.0, "C": 8.0, "H": 10.0, "N": 4.0},
    "ZIF (Co node)": {"Co": 1.0, "C": 8.0, "H": 10.0, "N": 4.0},
    "ZIF (Cu node)": {"Cu": 1.0, "C": 8.0, "H": 10.0, "N": 4.0},
    "nCoCuCeZIF (equimolar Co/Cu/Ce nodes)": {"Co": 1 / 3, "Cu": 1 / 3, "Ce": 1 / 3,
                                              "C": 8.0, "H": 10.0, "N": 4.0},
    "ZIF (all-Ce node — UPPER BOUND)": {"Ce": 1.0, "C": 8.0, "H": 10.0, "N": 4.0},
    "Ti-6Al-4V substrate (context)": {"Ti": 1.0},
}

# Layer thicknesses to classify against the electron range (cm). Canon: ZIF nanocrystals 40-80 nm
# aggregating into a porous layer (`01_03 §2.2`); the whole membrane stack is DELTA_MEMBRANE.
LAYERS_CM = {
    "single ZIF nanocrystal (80 nm)": 80e-7,
    "aggregated nanozyme film (1 µm)": 1e-4,
    "whole cathode membrane stack": DELTA_MEMBRANE,
}


def z_over_a(composition: dict[str, float]) -> tuple[float, float]:
    """<Z/A> and mean Z for a compound given as atom counts. Returns (Z/A, <Z>_mass-weighted)."""
    z_sum = sum(n * ELEMENTS[el][0] for el, n in composition.items())
    a_sum = sum(n * ELEMENTS[el][1] for el, n in composition.items())
    z_mass = sum(n * ELEMENTS[el][1] * ELEMENTS[el][0] for el, n in composition.items()) / a_sum
    return z_sum / a_sum, z_mass


def klein_nishina_total(alpha: float) -> float:
    """Total Compton cross-section per electron in units of r_e^2 (Klein-Nishina, closed form)."""
    a = alpha
    t1 = (1 + a) / a**2 * (2 * (1 + a) / (1 + 2 * a) - math.log(1 + 2 * a) / a)
    t2 = math.log(1 + 2 * a) / (2 * a)
    t3 = (1 + 3 * a) / (1 + 2 * a) ** 2
    return 2 * math.pi * (t1 + t2 - t3)


def mean_energy_transfer_fraction(alpha: float, n_steps: int = 200_000) -> tuple[float, float]:
    """Mean fraction of the photon energy given to the Compton electron, by INTEGRATING the
    differential Klein-Nishina cross-section over solid angle.

    Deliberately not a remembered closed form. The first draft of this script used a mis-recalled
    sigma_tr expression and printed a transfer fraction of 5.18 — an impossibility that only the
    physics, not the code, could flag. Integrating dsigma/dOmega uses one formula instead of two and
    is self-checking: the returned fraction is asserted into (0, 1), and the same integrand's zeroth
    moment is compared against the closed-form total below, so a typo in either shows up as a mismatch.

        dsigma/dOmega = (r_e^2 / 2) (k'/k)^2 (k'/k + k/k' - sin^2 theta),  k'/k = 1/(1 + alpha(1-cos))

    Returns (mean transfer fraction, total cross-section from the SAME integrand, in r_e^2).
    """
    total = 0.0
    transferred = 0.0
    d_theta = math.pi / n_steps
    for i in range(n_steps):
        theta = (i + 0.5) * d_theta
        ratio = 1.0 / (1.0 + alpha * (1.0 - math.cos(theta)))
        d_sigma = 0.5 * ratio**2 * (ratio + 1.0 / ratio - math.sin(theta) ** 2)
        weight = 2.0 * math.pi * math.sin(theta) * d_theta      # solid-angle element
        total += d_sigma * weight
        transferred += d_sigma * weight * (1.0 - ratio)
    return transferred / total, total


def katz_penfold_range_g_cm2(e_mev: float) -> float:
    """CSDA range of an electron, 0.01-3 MeV (Katz & Penfold 1952). g/cm2 — divide by density for cm."""
    return 0.412 * e_mev ** (1.265 - 0.0954 * math.log(e_mev))


def main() -> int:
    banner("HW.22 — ZIF radiosensitisation under Co-60: desk verdict (closed form)")

    # ── Q1. Where does the energy go, and how far ──
    alpha = E_GAMMA_MEV / M_E_MEV
    f_transfer, sigma_num = mean_energy_transfer_fraction(alpha)
    sigma_closed = klein_nishina_total(alpha)
    # Two guards, because a transport number that is silently wrong reads exactly like one that is right.
    assert 0.0 < f_transfer < 1.0, f"energy-transfer fraction out of physical range: {f_transfer}"
    assert abs(sigma_num / sigma_closed - 1.0) < 1e-3, (
        f"numeric and closed-form Klein-Nishina totals disagree: {sigma_num} vs {sigma_closed}")
    e_electron = f_transfer * E_GAMMA_MEV
    range_mev_g_cm2 = katz_penfold_range_g_cm2(e_electron)
    range_mev_cm = range_mev_g_cm2 / 1.0        # unit density (water-equivalent tissue/hydrogel)

    banner("Q1 — Compton kinematics: how far the deposited energy travels")
    print(f"  E_gamma = {E_GAMMA_MEV} MeV → alpha = {alpha:.3f}")
    print(f"  Klein-Nishina total sigma agrees closed-form vs numeric to "
          f"{abs(sigma_num / sigma_closed - 1.0):.1e} (guard)")
    print(f"  mean energy-transfer fraction = {f_transfer:.3f} → "
          f"mean Compton electron {e_electron * 1000:.0f} keV")
    print(f"  CSDA range of that electron (Katz-Penfold, unit density) = {range_mev_g_cm2:.3f} g/cm² "
          f"= {range_mev_cm * 10:.2f} mm")

    layer_rows = []
    print(f"\n  {'layer':<38s} {'thickness':>12s} {'t / R_CSDA':>12s} {'regime':>18s}")
    print(f"  {'-'*84}")
    for label, t_cm in LAYERS_CM.items():
        ratio = t_cm / range_mev_cm
        # A cavity whose thickness is <<1% of the electron range is Bragg-Gray by any textbook
        # criterion: it perturbs the electron fluence negligibly, so its dose is the medium's.
        regime = ("Bragg-Gray cavity" if ratio < 0.01
                  else "intermediate (Burlin)" if ratio < 1.0 else "own equilibrium")
        layer_rows.append({"layer": label, "thickness_cm": t_cm,
                           "thickness_over_csda_range": ratio, "cavity_regime": regime})
        print(f"  {label:<38s} {t_cm * 1e4:>9.2f} µm {ratio:>12.2e} {regime:>18s}")
    print("\n  → Every layer in the stack is orders of magnitude thinner than the electron range, so its")
    print("    dose is imposed by the electron fluence crossing it from the surrounding medium. A local")
    print("    excess of photon interactions inside the film CANNOT raise the dose there: the energy is")
    print("    carried out of the film by electrons whose range dwarfs it.")

    # ── Q2. The mass energy-absorption ratio (the DEF the caveat means) ──
    banner("Q2 — mass energy-absorption ratio at 1.25 MeV (Compton-dominated)")
    zoa_water, _ = z_over_a(MATERIALS["water (dose reference)"])
    mat_rows = []
    print(f"  {'material':<40s} {'<Z/A>':>7s} {'<Z>':>6s} {'DEF vs water':>13s} {'verdict':>12s}")
    print(f"  {'-'*84}")
    for label, comp in MATERIALS.items():
        zoa, z_mean = z_over_a(comp)
        # Per unit mass, Compton energy absorption is proportional to electron density = <Z/A>·N_A,
        # so at fixed photon energy the material ratio IS the <Z/A> ratio. Nothing else cancels.
        def_compton = zoa / zoa_water
        verdict = "ENHANCES" if def_compton > 1.0 else "no enhancement"
        mat_rows.append({"material": label, "z_over_a": round(zoa, 4), "mean_z": round(z_mean, 1),
                         "def_compton_vs_water": round(def_compton, 4),
                         "enhances": bool(def_compton > 1.0)})
        print(f"  {label:<40s} {zoa:>7.4f} {z_mean:>6.1f} {def_compton:>12.3f}× {verdict:>12s}")
    upper = max(mat_rows, key=lambda r: r["mean_z"] if "ZIF" in r["material"] else -1.0)
    print("\n  → Not one composition enhances. The physical upper bound (an all-Ce node — heavier than")
    print(f"    anything canon's `nCoCuCeZIF` can mean) sits at DEF {upper['def_compton_vs_water']:.3f}×,")
    print("    i.e. the heavy framework absorbs LESS per gram than the water it displaces.")

    # ── Q3. Invert it: how large would the neglected channels have to be ──
    banner("Q3 — falsification margin: how wrong would Q2 have to be")
    deficit = 1.0 - upper["def_compton_vs_water"]
    required_share = deficit / 1.0
    print("  Photoelectric and pair production are Z-dependent and are NOT computed here. Rather than")
    print(f"  assert they are negligible, invert: at the {upper['def_compton_vs_water']:.3f}× upper bound the")
    print(f"  Compton channel leaves a {deficit * 100:.1f} % deficit. For DEF to reach 1.0 a non-Compton")
    print(f"  channel would have to supply ≥ {required_share * 100:.1f} % of the ZIF's total mass energy")
    print("  absorption at 1.25 MeV while supplying ~0 % in water — and to matter it would then have to")
    print("  beat Q1 as well, which is geometric and indifferent to the coefficient. That percentage is")
    print("  the single number any lab check of this caveat would have to exceed.")

    # ── Q4. Why the kV literature does not transfer ──
    banner("Q4 — why the kV nanoparticle result does not transfer to Co-60")
    e_pe_mev = E_KV_REF_KEV / 1000.0
    range_kv_g_cm2 = katz_penfold_range_g_cm2(e_pe_mev)
    range_ratio = range_mev_g_cm2 / range_kv_g_cm2
    print(f"  A {E_KV_REF_KEV:.0f} keV photoelectron has CSDA range {range_kv_g_cm2 * 1e4:.2f} µm "
          f"(unit density) —")
    print("  that is the SAME order as the structure being protected, so energy released at the metal")
    print(f"  centre is deposited on it. At 1.25 MeV the range is ×{range_ratio:.0f} larger "
          f"({range_mev_cm * 10:.2f} mm),")
    print(f"  so the identical amount of extra energy is smeared over a volume ×{range_ratio ** 3:.0e} greater.")
    print("  Dose enhancement is a LOCALITY phenomenon, and Co-60 destroys the locality.")

    # ── Verdict ──
    banner("Verdict")
    print("  1. The physical radiosensitisation caveat on the low-dose gamma row does NOT hold at")
    print("     Co-60 energy, on two independent grounds: the deposition is non-local (Q1) and the")
    print("     mass coefficient moves the wrong way even under full equilibrium (Q2).")
    print("  2. Therefore `01_04 §6.3` Гілка A stands as specified: gamma on the LOADED anchor.")
    print("     Aseptic enzyme loading AFTER sterilisation is not required by this risk, and that")
    print("     matters because it is a factory-flow change, not a parameter.")
    print("  3. ⚠️ The residual is CHEMICAL, not dosimetric: redox-active Ce/Cu/Co can convert")
    print("     radiolytic H₂O₂ into hydroxyl radicals (Fenton-like). No photon-transport argument")
    print("     touches it, and its sign is genuinely open — the same nanozyme is chosen for its")
    print("     SOD/catalase-like activity, so it may scavenge as easily as amplify. It is measured")
    print("     directly by the Гілка A assay already in the plan (activity before/after 15 kGy),")
    print("     which should therefore be run WITH and WITHOUT the ZIF as its own control.")
    print("  4. ⚠️ Hypothesis, not measurement (00_06 §0): closed-form transport with literature")
    print("     constants. What it structurally cannot see — the chemical channel above, dose-rate")
    print("     effects, and any packaging (blister, N₂) that changes the radiolysis environment.")

    out = {
        "method": "closed-form photon transport: Klein-Nishina energy-transfer fraction + Katz-Penfold "
                  "CSDA range + <Z/A> mass energy-absorption ratio. Literature constants only; no DFT.",
        "gamma_source": {"energy_MeV": E_GAMMA_MEV, "alpha": round(alpha, 4),
                         "kn_energy_transfer_fraction": round(f_transfer, 4),
                         "mean_compton_electron_keV": round(e_electron * 1000, 1),
                         "csda_range_g_cm2": round(range_mev_g_cm2, 4),
                         "csda_range_mm_unit_density": round(range_mev_cm * 10, 3)},
        "cavity_classification": layer_rows,
        "mass_absorption_ratio": mat_rows,
        "falsification_margin": {
            "def_upper_bound_all_ce_node": upper["def_compton_vs_water"],
            "non_compton_share_required_for_def_1p0_pct": round(required_share * 100, 2),
            "note": "The photoelectric and pair channels are not computed. This is the share of total "
                    "mass energy absorption they would have to supply in the ZIF (and ~none in water) "
                    "for DEF to reach unity — the number a lab check would have to beat."},
        "kv_contrast": {"reference_photon_keV": E_KV_REF_KEV,
                        "photoelectron_csda_range_um": round(range_kv_g_cm2 * 1e4, 3),
                        "range_ratio_mev_over_kev": round(range_ratio, 1),
                        "volume_dilution_ratio": round(range_ratio ** 3, 1)},
        "verdict": ("Physical radiosensitisation by the ZIF nanozyme is REJECTED at Co-60 1.25 MeV on two "
                    "independent grounds. (1) Non-locality: the mean Compton electron is {:.0f} keV with a "
                    "{:.2f} mm CSDA range, so every layer of the stack is a Bragg-Gray cavity ({:.0e} of "
                    "the range at most) whose dose is imposed by the surrounding medium; a local excess "
                    "of interactions cannot raise it. (2) Coefficient direction: per unit mass Compton "
                    "absorption tracks <Z/A>, which FALLS with Z, so even the all-Ce upper-bound node "
                    "absorbs {:.3f}x water, not more. A non-Compton channel would have to supply "
                    "{:.1f}% of the ZIF's total absorption to reach DEF 1.0, and would still have to "
                    "beat (1). CONSEQUENCE: 01_04 6.3 Branch A stands as written - gamma on the LOADED "
                    "anchor; aseptic loading after sterilisation is NOT required by this risk. RESIDUAL "
                    "is chemical, not dosimetric (Fenton-like radiolysis on redox-active Ce/Cu/Co, sign "
                    "open because the same nanozyme is SOD/catalase-like) and is measured by the Branch "
                    "A activity assay already planned - run it with AND without the ZIF."
                    ).format(e_electron * 1000, range_mev_cm * 10,
                             max(r["thickness_over_csda_range"] for r in layer_rows),
                             upper["def_compton_vs_water"], required_share * 100),
        "caveats": "Hypothesis, not measurement (00_06 0). Closed-form transport with literature "
                   "constants; ZIF node stoichiometry is NOT fixed by canon, so the sweep brackets it "
                   "and quotes the all-Ce upper bound rather than inventing a formula. Structurally "
                   "blind to: the chemical radiolysis channel, dose-rate effects, and the packaging "
                   "environment (blister, N2) that sets how much water is present to radiolyse.",
    }
    OUT_JSON.write_text(json.dumps(out, indent=2))
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
