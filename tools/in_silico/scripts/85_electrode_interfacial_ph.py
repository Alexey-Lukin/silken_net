#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
85 — How far each coin electrode's OWN current moves the pH at its face in the media the Stage-2 letter can mean
(00_07 HW.5.IS, the 🤖 leg «оцінка інтерфейсного ΔpH на катоді» — its COIN half; the anchor CATHODE waits on HW.53,
whose answer decides which electrolyte it sees at all). One anchor number, conditional (2026-10-17, the leg «pH на грані
АНОДА в анкері»): the anchor's anode with its gap filled with stagnant sap — the state the HW.53 bench sets by hand, so
no bench run says whether a living stem keeps it (`anchor_anode`).

THE QUESTION. Laccase in ZIF inactivates at pH ≥ 6 (01_03 §3.2, the BOD row). The coin letter
(docs/protocols/procurement/anchor_coin_electrochem_rfq.md) says «Cathode medium: pH 4.5, air-exposed.» and names no
composition; the ratified sap (01_02 §2.1: malic acid 2.2 mM the only buffer, KOH sets the pH) is 5.75 for the
electrode tests and 4.5 ONLY for the uncoated ICP-MS series. So the letter leaves the cathode medium to the laboratory,
and this script prices the readings it allows (MEDIA): the sap brought to 4.5 · the sap at 5.75 (a one-compartment
cell, where the cathode shares the anode's medium) · a buffered cathode medium (the sap's salts, malic acid at 10 mM,
pH 4.5 — the medium the letter specifies since ⚖️ founder 2026-10-12, 01_03 §3.5). A standard laccase buffer (citrate, acetate at ~0.1 M) is NOT computed.
The ORR consumes one proton per electron (O₂ + 4H⁺ + 4e⁻ → 2H₂O); a weak buffer has to carry them to the face.
The anode is the mirror (beyond the leg's words, the same equation and the same letter): FAD-GDH wired by the Os
polymer releases one proton per electron at the face (FADH₂ → FAD + 2H⁺ + 2e⁻ through the mediator). N_H_ANODE runs
to 1.5 for the gluconolactone's acid in case it hydrolyses inside the layer; that needs hydrolysis within the seconds
the lactone spends crossing it, which is not sourced here — the 1.5 end is the unlikely one, and it sets the low δ*.

THE MECHANISM, AS AN EQUATION (the leg forbids reproducing Liu's FEM). A steady Nernst layer: each species crosses its
own layer δ_k; acid–base equilibrium holds everywhere; migration is neglected (the medium carries ≈ 10 mM of
indifferent salt); every malate species shares one D and total malate is held uniform. Both simplifications were
probed by the adversary of 2026-10-12 in its own scratch code — a 1-D Nernst–Planck film moved the supply by −1.5 …
−2.0 %, species-specific D with zero net malate flux stayed inside the single-D bracket — NOT reproduced here, so
those are a reviewer's readings, not this script's. The proton flux to a face at pH_s is
    J_H(pH_s) = D_mal·[N(pH_b) − N(pH_s)]/δ_mal + D_H·([H⁺]_b − [H⁺]_s)/δ_H,
with N the protons bound to solutes — malate, but for micromoles of bisulfate — (mol/L) from `67`'s speciation of the
recipe: the same constants and Davies activities that gave canon its buffer capacity, over every documented malate
reading `67` carries (Q6's set). OH⁻ is left out, as in `67` — so every face pH is held under 7 by assertion, and a
face whose malate is spent is reported as beyond this model, not given a number.

THE CATHODE ANSWER IS ALMOST δ-FREE. O₂ reaches the face through the same layer, j_O2 = 4F·D_O2·C_O2/δ_O2, so the
fraction f = F·J_H(6)/j_O2 of the O₂ transport limit at which the face reaches pH 6 depends on the hydrodynamics only
through the exponent p of D in each flux: 1 in a stagnant film, 2/3 in a convective (Levich) layer, 1/2 in a transient
semi-infinite layer — a CV, or a hold in a recessed window for its first hours (FILMS; superposition per species, which
the adversary's exact similarity solve put within a few % at the transient end). f moves far less with p than with
malate's D, which nobody has measured. f < 1: the face crosses pH 6 before the cathode runs out of oxygen.

THE ANODE ANSWER IS A THICKNESS. Its δ-free partner would be glucose transport, which this script does not compute —
no free-solution D of glucose is sourced in the tree — so the answer is δ*: the stagnant-film thickness above which
L4's current density brings the face to (i) pH 5.5, the acid end of the only measured pH pair of this enzyme's
kinetics (lib.constants PH_KINETICS_SYGMUND — the L4 bracket), and (ii) pH 4.5, the acid end of its measured
thermostability band (01_03 §1, Sygmund 2011). L4's current is the pH-7.4 laboratory CEILING (lib.constants J_MAX_25C:
50 mM phosphate, under flow); the pH bracket of ⚖️ 2026-09-18 is printed BESIDE it, never folded in. In a thick
unstirred layer glucose transport may cap the current below that ceiling first; δ* then says the ceiling current
cannot flow there with the face inside the band — not what the face pH is.

CONSTANTS are read, not typed (SOURCES, each with where it was read): H⁺ and the succinate stand-in from limiting
conductances (Apelblat & Barthel 1991/1992), O₂ diffusion from Han & Bartels 1996 (its abstract's formula — the one
reading in hand), O₂ solubility from the USGS table on Benson & Krause. Malate's own D was NOT found: it is bracketed
between hydrogen citrate (larger) and hydrogen succinate (smaller); the succinate value is a best-fit its own source
flags, and a C4 monoanion likely sits lower — so the high end is probably high, and it is the end that keeps the
cathode face under pH 6: the bracket errs toward «no risk». The unstirred cell's δ in water, 150–1000 µm, is the range
Katona et al. 2021 review (their 135 µm is a DMF solution, left out).

CONTROLS that can fail (raise, never warn):
  1. the proton bookkeeping N + [H⁺] between two pH values equals the base `67` titrates between them, every reading;
  2. Liu et al.'s FEM (the leg's own source), the one interfacial pH their SI gives at a stated current — read off the
     axes of SI Fig. S4, ≈ 5.59 at the centre of a 300 µm disk at ≈ 65.6 µA/cm², 10 mM citrate, air: a film with
     THEIR constants, their species D and zero net citrate flux, δ = the disk radius (a uniform-flux disk's centre),
     lands within 0.05; and the single-D form this script uses, run at their lowest and highest species D, brackets
     that value. Its resolving power is printed: ± 0.05 pH there is a band of δ (≈ ±25 %), so it catches a missing
     buffer term or a factor-2 error, not a 20 % one; and free H⁺ carries a few % of the supply at their point against
     a larger share at the coin cathode, so it does not vouch for that term.

WHAT THIS DOES NOT SETTLE, up front: which medium the laboratory will use and its convection (the letter fixes
neither); the pH INSIDE the coatings (the anode's hydrogel and membrane, the cathode's porous layer) — protons are
made or consumed under them, so the shift at the enzyme is LARGER than at the outer face computed here, and stirring
cannot remove the coatings' own resistance; the 0.25 M NaCl steps of test D (salting-out lowers C_O2, which raises f);
whether a face at pH 6 inactivates laccase reversibly (Wang 2020 is the threshold canon quotes, not a kinetics).

Genre = `67`: literature constants plus closed-form self-checks, answering a lab-gated question before the lab.
Run:  python tools/in_silico/scripts/85_electrode_interfacial_ph.py      # seconds
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

from scipy.optimize import brentq

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    A_ELECTRODE,
    BQ25570_PIN_CS_UW,
    BQ25570_VIN_CS_MAX_MV,
    BQ25570_VIN_CS_TYP_MV,
    CACHE_DIR,
    F_CONST,
    J_MAX_25C,
    KM_GLUCOSE,
    R_GAS,
    REPO_ROOT,
)
from lib.kinetics import ph_current_ratio
from lib.utils import banner

SI_DESCRIPTION = ("How far each Ti-coin electrode's own current shifts the pH at its face in the media the test letter "
                  "allows, from a steady diffusion-layer equation: the cathode as a fraction of its oxygen supply limit, "
                  "the anode as the diffusion-layer thickness its predicted current tolerates; and the anchor's anode, "
                  "conditional on sap filling its gap, as the current at which its face leaves the enzyme's pH band.")  # its row in the paper SI (72): English, no repo jargon
SCRIPTS = Path(__file__).resolve().parent
OUT = CACHE_DIR / "kinetics" / "electrode_interfacial_ph.json"


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod            # 67 declares dataclasses, which look their module up by name
    spec.loader.exec_module(mod)
    return mod


S67 = _load("s67_sap", "67_sap_recipe_saturation.py")   # the ratified recipe and its speciation — one home

# ── Transport and solubility at the coin's 20 and 25 °C (01_03 §3.5), each READ in its source (SOURCES), none typed
# from memory. A diffusion coefficient from a limiting conductance by Nernst–Einstein, D = R·T·λ/(|z|·F²), λ per mole
# of charge — R·T·λ/F² in J/mol · S·cm²/mol ÷ (C/mol)² is cm²/s. ──
TEMPS_C = (20.0, 25.0)
LAMBDA_H = {25.0: 349.85, 20.0: 390.0 - 64.04}    # S·cm²/mol — 20 °C: Λ°(H₃Cit) − λ°(⅓Cit³⁻), same table
LAMBDA_HSUCC_25 = 47.0                            # S·cm²/mol — hydrogen succinate, 25 °C (a best-fit parameter)
LAMBDA_SUCC_EQ = {25.0: 56.20, 20.0: 49.92}       # S·cm²/equiv — ½ succinate²⁻
D_HCIT_LIU = 6.12e-6                              # cm²/s — HCit²⁻ as Liu's model uses it (SI Table S1; T unprinted)
O2_MG_L_AIR = {25.0: 8.26, 20.0: 9.09}            # mg/L — fresh water, 760 mmHg, air saturation
M_O2 = 31.998                                     # g/mol
SOURCES = {
    "D_H": "Apelblat & Barthel 1991, Z. Naturforsch. 46a, 131 (doi:10.1515/zna-1991-1-222): λ°(H⁺) = 349.85 at "
           "25 °C as used on p. 135; 20 °C from Table 4 as Λ°(H₃Cit) − λ°(⅓Cit³⁻) = 390 − 64.04 (DERIVED — the 25 °C "
           "row holds the same identity, 422 = 349.85 + 72.05)",
    "D_O2": "Han & Bartels 1996, J. Phys. Chem. 100, 5597 (doi:10.1021/jp952903y): log₁₀ D = −4.410 + 773.8/T − "
            "(506.4/T)², as printed in the ABSTRACT — the full text was not reached, and no second primary was read "
            "(Ferrell & Himmelblau 1967 · Wise & Houghton 1966 paywalled); Liu et al. use 1.99e-9 m²/s",
    "C_O2": "USGS 2020, Techniques and Methods 9-A6.2 (doi:10.3133/tm9A6.2), Table 6.2-2, 760 mmHg, salinity 0 — built "
            "on Benson & Krause 1980/1984",
    "D_mal": "NOT FOUND for malic acid or its anions — bracketed between a LARGER and a SMALLER dicarboxylate: the "
             "low end is hydrogen citrate as Liu et al. model it (SI Table S1), the high end hydrogen succinate "
             "(malate = hydroxysuccinate) from Apelblat & Barthel 1992, Z. Naturforsch. 47a, 493 "
             "(doi:10.1515/zna-1992-0309), λ°(HSucc⁻) = 47.0 on p. 497, flagged there as a best-fit value and above "
             "what a C4 monoanion should carry — likely high; both ends move to 20 °C with succinate²⁻'s own ratio, "
             "λ°(½Succ²⁻) 49.92 / 56.20 of Table 2",
    "delta_natural_convection": "Katona et al. 2021, J. Electrochem. Soc. 168, 031512 (doi:10.1149/1945-7111/abeb29, "
                                "open access), Introduction: δ under natural convection «from near 250 μm … to between "
                                "500 and 1000 μm» over the solutions it reviews; Amatore's aqueous ferrocyanide "
                                "measurements 150–250 μm (the 135 μm it also lists is a DMF solution — left out); O₂ "
                                "reduction in 0.6 M NaCl ≈ 800 μm",
}
DELTA_NATURAL_CONVECTION_UM = (150.0, 1000.0)     # the unstirred aqueous cell's range, SOURCES["delta_natural_convection"]


def nernst_einstein(lam: float, z: int, t_c: float) -> float:
    return R_GAS * (t_c + 273.15) * lam / (abs(z) * F_CONST ** 2)


def d_o2(t_c: float) -> float:
    t_k = t_c + 273.15
    return 10.0 ** (-4.410 + 773.8 / t_k - (506.4 / t_k) ** 2)


def d_h(t_c: float) -> float:
    return nernst_einstein(LAMBDA_H[t_c], 1, t_c)


def c_o2(t_c: float) -> float:                    # mol/L
    return O2_MG_L_AIR[t_c] / M_O2 * 1e-3


def d_mal(t_c: float) -> dict:                    # one D for every malate species — the two ends of the bracket
    ratio = nernst_einstein(LAMBDA_SUCC_EQ[t_c], 2, t_c) / nernst_einstein(LAMBDA_SUCC_EQ[25.0], 2, 25.0)
    return {"citrate_like": D_HCIT_LIU * ratio, "succinate_like": nernst_einstein(LAMBDA_HSUCC_25, 1, 25.0) * ratio}


# ── Thresholds, media and currents — each from its canon home ──
PH_LACCASE_OFF = 6.0              # laccase in ZIF inactivates at pH ≥ 6 (01_03 §3.2, Wang 2020)
PH_MODEL_CEILING = 6.99           # OH⁻ is not modelled: a face beyond this is «malate spent», never a number
PH_SAP = 5.75                     # the ratified set-point (01_02 §2.1) — the letter's electrode-test medium
PH_ANODE_KINETIC_EDGE = 5.5       # acid end of PH_KINETICS_SYGMUND — the only measured pH pair of the L4 bracket
PH_ANODE_STABILITY_EDGE = 4.5     # acid end of the measured thermostability band (01_03 §1, Sygmund 2011)
BUFFERED_MALIC_MM = 10.0          # the cathode medium of ⚖️ 2026-10-12 (01_03 §3.5) — the sap's salts, more malic acid
GLUCOSE_HOLD_MM = 10.0            # the letter's hold concentration (01_03 §3.5)
GLUCOSE_SERIES_TOP_MM = 50.0      # top of the day-0 glucose series (01_03 §3.5)
LOAD_B_A = 25e-6                  # the letter's load point B (02_03 §1.5 cold-start pair), on one face (A_ELECTRODE)
N_H_ANODE = (1.0, 1.5)            # protons per electron at the anode face: the mediator's own … + the lactone's acid
FILMS = (("stagnant", 1.0), ("Levich", 2.0 / 3.0), ("transient", 0.5))   # flux ∝ D^p

READINGS = [sc for sc in S67.SCENARIOS if sc.key != "hard_bound"]   # Q6's set: every documented malate reading
TOTALS = S67.totals_mm(S67.RATIFIED_POINT_MM)
TOTALS_BUFFERED = S67.totals_mm({**S67.RATIFIED_POINT_MM, "malic": BUFFERED_MALIC_MM})
MEDIA = {   # name: (totals, bulk pH, what it is)
    "sap_pH4.5": (TOTALS, 4.5, "the ratified sap brought to 4.5 — a laboratory's likeliest reading of the letter"),
    "sap_pH5.75": (TOTALS, PH_SAP, "the ratified sap at its set-point — the cathode in a one-compartment cell"),
    "buffered_pH4.5": (TOTALS_BUFFERED, 4.5, f"the sap's salts with malic acid at {BUFFERED_MALIC_MM:.0f} mM, pH 4.5 — "
                                             "the letter's cathode medium since ⚖️ 2026-10-12"),
}


def face_state(ph: float, sc, t_c: float = 25.0, totals: dict | None = None) -> dict:
    """Protons bound to solutes and free H⁺ (mol/L) at a fixed pH, from `67`'s speciation at t_c. Malate carries all of
    N but micromoles (bisulfate); they travel with D_mal here, which their own D (≈ sulfate's) barely changes."""
    assert ph < 7.0, f"pH {ph} — OH⁻ is not modelled (as in 67)"
    model = S67.model_for(sc, t_c)
    sol = S67.speciate(model, totals or TOTALS, ph)
    bound = sum(dict(sp.stoich).get("H", 0) * sol.conc.get(sp.name, 0.0) for sp in model.cs.species)
    return {"bound": bound, "h": 10.0 ** (-ph - sol.log_gamma[1]), "base": sol.base_mol_l,
            "ionic": sol.ionic_strength}


def proton_supply(ph_b: float, ph_s: float, sc, d_buf: float, p: float, t_c: float = 25.0,
                  totals: dict | None = None) -> float:
    """Σ D_k^p·Δc_k (cm^(2p)/s^p · mol/L): the proton flux toward the face × δ^p. Positive = toward the face."""
    b, s = face_state(ph_b, sc, t_c, totals), face_state(ph_s, sc, t_c, totals)
    return d_buf ** p * (b["bound"] - s["bound"]) + d_h(t_c) ** p * (b["h"] - s["h"])


def o2_supply(p: float, t_c: float) -> float:
    return 4.0 * d_o2(t_c) ** p * c_o2(t_c)


def control_titration() -> dict:
    """Control 1: N + [H⁺] between two pH values equals the strong base `67` needs between them."""
    worst = 0.0
    for sc in READINGS:
        for lo, hi in ((4.5, PH_LACCASE_OFF), (PH_ANODE_STABILITY_EDGE, PH_SAP)):
            a, b = face_state(lo, sc, 20.0), face_state(hi, sc, 20.0)
            ours = (a["bound"] + a["h"]) - (b["bound"] + b["h"])
            worst = max(worst, abs(ours - (b["base"] - a["base"])))
    assert worst < 1e-9, f"proton bookkeeping departs from 67's titration by {worst:.1e} mol/L"
    return {"max_abs_dev_mol_l": worst}


# ── Control 2: Liu … Mazurenko, J. Am. Chem. Soc. 2026, doi:10.1021/jacs.6c15657 (the CC-BY accepted manuscript, HAL
# hal-05786271, and its SI). Their 2D-axisymmetric FEM of a bilirubin-oxidase microdisk (r = 150 µm, stagnant, air,
# 0.5 V, 300 s) in 10 mM citrate pH 5.4 + Na₂SO₄: current density ≈ −65.6 µA/cm² and pH at the electrode CENTRE ≈ 5.59
# (SI Fig. S4 A/B — READ OFF THE AXES, whose ticks step by 0.01; no table prints them). A disk under uniform flux q sees
# Δc = q·a/D at its centre (the half-space Green's function), so δ = a. Their constants: thermodynamic pKa 3.128 ·
# 4.761 · 6.4 (SI §3), Davies for the citrate anions and Truesdell–Jones for H⁺ (A = 0.5115, B = 3.2914, a₀ = 0.478 nm,
# b = 0.24 — SI eqs S8–S9), species D from SI Table S1. I for the 10 mM run is not printed (0.077 M is, for 1 mM, SI
# Fig. S2) → both ends of [0.077, 0.10] are checked; the result is monotone in I and moves < 0.01 across it.
LIU = {"pka": (3.128, 4.761, 6.4), "A": 0.5115, "B": 3.2914, "a0_h_nm": 0.478, "b_h": 0.24,
       "D": (6.57e-6, 9.77e-6, 6.12e-6, 6.4e-6), "D_H": 9.311e-5, "c_buf_mol_l": 10e-3, "ph_bulk": 5.4,
       "radius_cm": 150e-4, "j_A_cm2": 65.6e-6, "ph_centre": 5.59, "ionic": (0.077, 0.10), "tol_pH": 0.05}


def _liu_species(ph: float, ionic: float) -> tuple[list, float]:
    """Fractions of H₃Cit, H₂Cit⁻, HCit²⁻, Cit³⁻ at an activity pH, and the free H⁺ concentration (mol/L)."""
    s = math.sqrt(ionic)
    g = [10.0 ** (-LIU["A"] * z * z * (s / (1 + s) - 0.3 * ionic)) for z in (1, 2, 3)]
    g_h = 10.0 ** (-LIU["A"] * s / (1 + LIU["B"] * LIU["a0_h_nm"] * s) + LIU["b_h"] * ionic)
    a_h, k = 10.0 ** -ph, [10.0 ** -pk for pk in LIU["pka"]]
    r1 = k[0] / (a_h * g[0])
    r2 = r1 * k[1] * g[0] / (a_h * g[1])
    r3 = r2 * k[2] * g[1] / (a_h * g[2])
    x = (1.0, r1, r2, r3)
    return [v / sum(x) for v in x], a_h / g_h


def _liu_supply(ph_s: float, ionic: float, ds: tuple, conserve: bool) -> tuple[float, float]:
    """(total, free-H⁺ part) of the proton supply × δ (cm²/s · mol/L). With `conserve`, the face's total citrate is the
    one that makes the net citrate flux zero — reference-free proton counting; without it, one D for all species."""
    (ab, hb), (as_, hs) = _liu_species(LIU["ph_bulk"], ionic), _liu_species(ph_s, ionic)
    c_b = LIU["c_buf_mol_l"]
    c_s = c_b * sum(d * a for d, a in zip(ds, ab, strict=True)) / sum(d * a for d, a in zip(ds, as_, strict=True)) \
        if conserve else c_b
    bound = sum(n * d * (c_b * a - c_s * a2) for n, d, a, a2 in zip((3, 2, 1, 0), ds, ab, as_, strict=True))
    free = LIU["D_H"] * (hb - hs)
    return bound + free, free


def control_liu() -> dict:
    j, a = LIU["j_A_cm2"], LIU["radius_cm"]
    def face_ph(ionic, ds, conserve):
        return brentq(lambda ph: F_CONST * _liu_supply(ph, ionic, ds, conserve)[0] * 1e-3 / a - j,
                      LIU["ph_bulk"] + 1e-6, 6.99)
    got, single = {}, {}
    for ionic in LIU["ionic"]:
        got[ionic] = face_ph(ionic, LIU["D"], True)
        assert abs(got[ionic] - LIU["ph_centre"]) <= LIU["tol_pH"], \
            f"film gives pH {got[ionic]:.3f} where Liu's FEM gives ≈ {LIU['ph_centre']} (I = {ionic})"
        lo, hi = (face_ph(ionic, (d,) * 4, False) for d in (min(LIU["D"]), max(LIU["D"])))
        assert hi < got[ionic] < lo, f"the single-D form does not bracket the conserving film at I = {ionic}"
        single[ionic] = (hi, lo)
    ionic = LIU["ionic"][0]
    band = [F_CONST * _liu_supply(LIU["ph_centre"] + s * LIU["tol_pH"], ionic, LIU["D"], True)[0] * 1e-3 / j / a
            for s in (-1, 1)]
    tot, free = _liu_supply(got[ionic], ionic, LIU["D"], True)
    return {"source": "Liu et al. 2026, SI Fig. S4 (10 mM citrate, air, 300 s, centre of a 300 µm disk), read off the axes",
            "fem_pH_centre": LIU["ph_centre"], "film_pH_centre": {str(k): round(v, 3) for k, v in got.items()},
            "single_D_bracket_pH": {str(k): [round(v[0], 3), round(v[1], 3)] for k, v in single.items()},
            "tolerance_pH": LIU["tol_pH"],
            "passing_delta_over_radius": [round(band[0], 2), round(band[1], 2)],
            "free_H_share_of_supply": round(free / tot, 3),
            "bound": "the linear regime only: in their 1 mM buffer the FEM redistributes current over the disk, which "
                     "a uniform-flux film cannot; a planar 2 cm² face is far closer to the film"}


def _f(medium: str, ph_s: float, sc, d_buf: float, p: float, t_c: float) -> float:
    totals, ph_b, _ = MEDIA[medium]
    return proton_supply(ph_b, ph_s, sc, d_buf, p, t_c, totals) / o2_supply(p, t_c)


def cathode() -> dict:
    out = {}
    for medium, (totals, ph_b, what) in MEDIA.items():
        rows = []
        for t_c in TEMPS_C:
            for sc in READINGS:
                for end, d_buf in d_mal(t_c).items():
                    for film, p in FILMS:
                        f6 = _f(medium, PH_LACCASE_OFF, sc, d_buf, p, t_c)
                        f_spent = _f(medium, PH_MODEL_CEILING, sc, d_buf, p, t_c)
                        at_limit = None if f_spent < 1.0 else brentq(
                            lambda ph, m=medium, sc=sc, d=d_buf, p=p, t=t_c: _f(m, ph, sc, d, p, t) - 1.0,
                            ph_b + 1e-6, PH_MODEL_CEILING)
                        rows.append({"t_c": t_c, "reading": sc.key, "D_end": end, "D_mal": d_buf, "film": film,
                                     "f_pH6": f6, "f_malate_spent": f_spent, "face_pH_at_O2_limit": at_limit})

        def rng(sel, key="f_pH6", rows=rows):
            vals = [r[key] for r in rows if sel(r)]
            return [round(min(vals), 3), round(max(vals), 3)]
        reached = [r["face_pH_at_O2_limit"] for r in rows if r["face_pH_at_O2_limit"] is not None]
        out[medium] = {
            "what": what, "bulk_pH": ph_b, "ionic_strength_25C": round(face_state(ph_b, S67.SC["selected"], 25.0,
                                                                                 totals)["ionic"], 4),
            "f_pH6": rng(lambda r: True),
            "f_pH6_by_D_end": {e: rng(lambda r, e=e: r["D_end"] == e) for e in ("citrate_like", "succinate_like")},
            "f_pH6_by_film": {fm: rng(lambda r, fm=fm: r["film"] == fm) for fm, _ in FILMS},
            "f_malate_spent": rng(lambda r: True, "f_malate_spent"),
            "rows_crossing_pH6_below_O2_limit": sum(r["f_pH6"] < 1.0 for r in rows),
            "rows_beyond_model_at_O2_limit": sum(r["face_pH_at_O2_limit"] is None for r in rows),
            "face_pH_at_O2_limit_where_reached": [round(min(reached), 2), round(max(reached), 2)] if reached else None,
            "rows": len(rows)}
        if medium == "sap_pH4.5":
            out[medium]["row_table"] = rows
    j_b = LOAD_B_A / A_ELECTRODE
    delta_b = [F_CONST * proton_supply(4.5, PH_LACCASE_OFF, sc, d, 1.0, t_c) * 1e-3 / j_b
               for t_c in TEMPS_C for sc in READINGS for d in d_mal(t_c).values()]
    sc, d_lo = S67.SC["selected"], d_mal(25.0)["citrate_like"]
    free_share = d_h(25.0) * (face_state(4.5, sc)["h"] - face_state(PH_LACCASE_OFF, sc)["h"]) \
        / proton_supply(4.5, PH_LACCASE_OFF, sc, d_lo, 1.0)
    return {"media": out, "threshold_pH": PH_LACCASE_OFF,
            "load_B_uA_cm2": round(j_b * 1e6, 2), "load_B_area_cm2": A_ELECTRODE,
            "load_B_delta_star_mm_sap_pH4.5": [round(min(delta_b) * 10, 2), round(max(delta_b) * 10, 2)],
            "free_H_share_of_supply_sap_pH4.5_low_D": round(free_share, 3)}


def anode() -> dict:
    j_ceiling = {g: J_MAX_25C * g / (KM_GLUCOSE + g) for g in (GLUCOSE_HOLD_MM, GLUCOSE_SERIES_TOP_MM)}
    ratios = [ph_current_ratio(GLUCOSE_HOLD_MM, form) for form in ("wt", "rec")]
    currents = {"ceiling_hold": j_ceiling[GLUCOSE_HOLD_MM], "ceiling_series_top": j_ceiling[GLUCOSE_SERIES_TOP_MM],
                "ph_bracket_hold_low": j_ceiling[GLUCOSE_HOLD_MM] * min(ratios),
                "ph_bracket_hold_high": j_ceiling[GLUCOSE_HOLD_MM] * max(ratios),
                "load_B": LOAD_B_A / A_ELECTRODE}
    out = {}
    for edge in (PH_ANODE_KINETIC_EDGE, PH_ANODE_STABILITY_EDGE):
        per = {}
        for name, j in currents.items():
            deltas = {n: [F_CONST * -proton_supply(PH_SAP, edge, sc, d, 1.0) * 1e-3 / (n * j)
                          for sc in READINGS for d in d_mal(25.0).values()] for n in N_H_ANODE}
            every = [x for v in deltas.values() for x in v]
            per[name] = {"j_uA_cm2": round(j * 1e6, 1),
                         "delta_star_um": [round(min(every) * 1e4, 1), round(max(every) * 1e4, 1)],
                         "delta_star_um_n1": [round(min(deltas[1.0]) * 1e4, 1), round(max(deltas[1.0]) * 1e4, 1)]}
        out[f"face_pH_{edge}"] = per
    return {"bulk_pH": PH_SAP, "t_c": 25.0, "glucose_mM": {"hold": GLUCOSE_HOLD_MM, "series_top": GLUCOSE_SERIES_TOP_MM},
            "n_H_per_electron": list(N_H_ANODE), "ph_ratio_hold": [round(min(ratios), 3), round(max(ratios), 3)],
            "delta_star": out, "glucose_transport": "not computed — no free-solution D of glucose is sourced in the tree"}


CEM = REPO_ROOT / "tools/cad/cem"
ZONE1_SKUS = sorted(p for p in CEM.glob("anchor_zone1.*.json") if not p.name.endswith(".golden.json"))
ANCHOR_GAP_STATES = {   # the three states 84 and the HW.53 bench name for the gap between the gyroid and the bore wall
    "sap_gap": "the gap filled with sap, stagnant — computed below",
    "air_gap": "no electrolyte in the gap — 84 leaves it not modelled (layer 1 then runs through contact points only)",
    "ingrown": "wood in the gap: proton and malate transport through living sapwood has no source in the tree — not computed",
}
# The anchor's own cold-start draw: the BQ25570 needs P_IN(CS) at V_IN(CS) (02_03 §1.5) — typ and the worst-case column
# the Stage-2 gates judge (V_IN(CS) MAX). Not the coin letter's load point B, which is a coin measurement.
COLD_START_UA = {"typ": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_TYP_MV * 1e3,
                 "worst": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_MAX_MV * 1e3}


def anchor_geometry(zone1_path) -> dict:
    """The gyroid's envelope and the bore it stands in, read from the CEMs as 84 reads them: one Ø15 step takes the anode
    and the sleeve (01_01 §4.3 C · 01_04 §3.1 item 2 · cathode_ionic_path_bench §2.1), so the bore wall is the Zone-2
    sleeve's OD; the lattice length is the exposed anode (⚖️ HW.26 G1: only the lock's shank enters the sleeve). One
    sleeve manifest serves every Zone-1 SKU, so the gap narrows as the lattice thickens."""
    zone1 = json.loads(zone1_path.read_text(encoding="utf-8"))
    sleeve = json.loads((CEM / "zone2_sleeve.json").read_text(encoding="utf-8"))
    r_a = zone1["outer_diameter_mm"] / 20.0                                     # cm
    r_b = (sleeve["bore_diameter_mm"] / 2.0 + sleeve["wall_thickness_mm"]) / 10.0
    length = zone1["length_mm"] / 10.0
    if r_b <= r_a:
        raise SystemExit(f"{zone1['name']}: the lattice fills the bore — no gap to fill with sap")
    return {"sku": zone1["name"], "anode_radius_cm": r_a, "bore_radius_cm": r_b, "gap_mm": round((r_b - r_a) * 10.0, 3),
            "lattice_length_cm": length, "envelope_lateral_area_cm2": 2.0 * math.pi * r_a * length,
            "bottom_cap_over_envelope": r_a / (2.0 * length), "annulus_delta_cm": r_a * math.log(r_b / r_a)}


def anchor_anode() -> dict:
    """The anchor's anode with its gap FILLED WITH STAGNANT SAP — the state the HW.53 bench SETS by hand (it fills the gap
    with the recipe), so the bench cannot say whether a living stem keeps sap there; this is the answer conditional on that
    state, per Zone-1 SKU. The ratified sap at its set-point lies stagnant across the annulus between the gyroid's envelope
    and the bore wall, the bulk at the wall; steady radial diffusion in an annulus gives, per unit of the ENVELOPE's area,
    the exact film δ = r_a·ln(r_b/r_a). Output: the envelope current density and the whole anode's current at which the
    face reaches each edge, against the anchor's own cold-start draw (COLD_START_UA). The current is a bracket: its low end
    is the envelope alone, its high end adds the bottom cap at the envelope's flux density (r_a/2L more; the cap faces the
    bore's end, whose gap no manifest gives).
    WHICH SIDE. Against the enzyme inside the lattice these currents are upper bounds: protons are made inside it, and the
    wood wall adds its own resistance. Effects the other way are NOT in: migration (a few per cent, the coin block's own
    figure), any flow through the gap (a stagnant film is the thickest it can be) and a CO₂/HCO₃⁻ buffer the recipe lacks —
    each raises the currents. In a stagnant film ~1.7 mm thick the lactone has about δ²/D ≈ an hour to hydrolyse inside
    it, so the n_H = 1.5 end is no longer the unlikely one it is on the coin; acid made inside the film moves the face
    less than acid made at it, so the truth lies between the two n_H ends."""
    out = {"states": ANCHOR_GAP_STATES, "cold_start_uA": {k: round(v, 1) for k, v in COLD_START_UA.items()},
           "by_sku": {}}
    for path in ZONE1_SKUS:
        g = anchor_geometry(path)
        per = {"geometry": g}
        for edge in (PH_ANODE_KINETIC_EDGE, PH_ANODE_STABILITY_EDGE):
            j = {n: [F_CONST * -proton_supply(PH_SAP, edge, sc, d, 1.0) * 1e-3 / (n * g["annulus_delta_cm"])
                     for sc in READINGS for d in d_mal(25.0).values()] for n in N_H_ANODE}
            every = [x for v in j.values() for x in v]
            lo = min(every) * g["envelope_lateral_area_cm2"] * 1e6
            hi = max(every) * g["envelope_lateral_area_cm2"] * (1.0 + g["bottom_cap_over_envelope"]) * 1e6
            per[f"face_pH_{edge}"] = {
                "j_envelope_uA_cm2": [round(min(every) * 1e6, 2), round(max(every) * 1e6, 2)],
                "i_anode_uA": [round(lo, 1), round(hi, 1)],
                "i_anode_uA_n1": [round(min(j[1.0]) * g["envelope_lateral_area_cm2"] * 1e6, 1),
                                  round(max(j[1.0]) * g["envelope_lateral_area_cm2"] * (1.0 + g["bottom_cap_over_envelope"]) * 1e6, 1)],
                "crossed_below_cold_start": {k: {"in_every_reading": hi < v, "in_some_reading": lo < v}
                                             for k, v in COLD_START_UA.items()}}
        out["by_sku"][g["sku"]] = per
    return out


def diagnostic_medium() -> dict:
    """The anode's day-0 check of ⚖️ 2026-10-12 (01_03 §3.5): the ratified sap at 5.75 with malic acid at BUFFERED_MALIC_MM —
    what it changes besides the buffer (ionic strength, KOH) and how much capacity it adds down to pH 4.5."""
    sc, m = S67.SC["selected"], S67.model_for(S67.SC["selected"], 25.0)
    base, strong = S67.speciate(m, TOTALS, PH_SAP), S67.speciate(m, TOTALS_BUFFERED, PH_SAP)
    d_lo = d_mal(25.0)["citrate_like"]
    gain = (proton_supply(PH_SAP, PH_ANODE_STABILITY_EDGE, sc, d_lo, 1.0, 25.0, TOTALS_BUFFERED)
            / proton_supply(PH_SAP, PH_ANODE_STABILITY_EDGE, sc, d_lo, 1.0, 25.0, TOTALS))
    return {"malic_mM": BUFFERED_MALIC_MM, "pH": PH_SAP,
            "ionic_strength_mol_l": [round(base.ionic_strength, 4), round(strong.ionic_strength, 4)],
            "koh_mM": [round(base.base_mol_l * 1e3, 2), round(strong.base_mol_l * 1e3, 2)],
            "capacity_gain_to_pH_4.5": round(gain, 2)}


def main() -> int:
    banner("HW.5.IS — pH at the coin electrodes' faces under their own current (coin half; anchor → HW.53)")
    checks = {"titration_vs_67": control_titration(), "liu_fem_point": control_liu()}
    liu = checks["liu_fem_point"]
    print(f"  control 2 (Liu FEM, centre ≈ {LIU['ph_centre']}): conserving film {liu['film_pH_centre']}, single-D "
          f"bracket {liu['single_D_bracket_pH']}, passes for δ/a in {liu['passing_delta_over_radius']}")
    cat, ano, diag, anc = cathode(), anode(), diagnostic_medium(), anchor_anode()
    for name, m in cat["media"].items():
        print(f"  cathode in {name}: f(pH 6) {m['f_pH6']} — citrate-like D {m['f_pH6_by_D_end']['citrate_like']}, "
              f"succinate-like {m['f_pH6_by_D_end']['succinate_like']}; crosses below the O₂ limit in "
              f"{m['rows_crossing_pH6_below_O2_limit']}/{m['rows']}, face at the O₂ limit "
              f"{m['face_pH_at_O2_limit_where_reached']} ({m['rows_beyond_model_at_O2_limit']} beyond the model)")
    print(f"    load B ({cat['load_B_uA_cm2']} µA/cm²) reaches pH 6 in the sap at 4.5 only for δ ≥ "
          f"{cat['load_B_delta_star_mm_sap_pH4.5']} mm")
    for edge, per in ano["delta_star"].items():
        print(f"  anode, sap at pH {PH_SAP} → {edge}:")
        for name, v in per.items():
            print(f"    {name:22s} j = {v['j_uA_cm2']:7.1f} µA/cm²  δ* = {v['delta_star_um']} µm (n_H = 1: "
                  f"{v['delta_star_um_n1']})")
    print(f"  anode check medium (malic {BUFFERED_MALIC_MM:.0f} mM, pH {PH_SAP}): capacity ×{diag['capacity_gain_to_pH_4.5']}, "
          f"I {diag['ionic_strength_mol_l']}")
    cs = anc["cold_start_uA"]
    print(f"  anchor anode, gap filled with stagnant sap — against its own cold-start draw {cs['typ']} (typ) · "
          f"{cs['worst']} µA (worst, V_IN(CS) MAX):")
    for sku, per in anc["by_sku"].items():
        ag = per["geometry"]
        print(f"    {sku}: Ø{20 * ag['anode_radius_cm']:g} in Ø{20 * ag['bore_radius_cm']:g}, gap {ag['gap_mm']} mm, "
              f"δ {10 * ag['annulus_delta_cm']:.2f} mm, envelope {ag['envelope_lateral_area_cm2']:.1f} cm² (+cap "
              f"{100 * ag['bottom_cap_over_envelope']:.1f} %) — "
              + " · ".join(f"{edge}: {v['i_anode_uA']} µA (below worst cold start: every "
                           f"{v['crossed_below_cold_start']['worst']['in_every_reading']}, some "
                           f"{v['crossed_below_cold_start']['worst']['in_some_reading']})"
                           for edge, v in per.items() if edge != "geometry"))
    out = {"script": Path(__file__).name,
           "question": "pH at the Stage-2 coin electrodes' faces under their own current, in the media the letter allows",
           "scope": "coin half of the 00_07 HW.5.IS leg, plus the anchor ANODE conditional on a sap-filled gap; the anchor "
                    "cathode waits on HW.53, and which gap state a living stem keeps is not known",
           "recipe_mM": S67.RATIFIED_POINT_MM, "readings": [sc.key for sc in READINGS], "t_c": list(TEMPS_C),
           "constants": {f"{t_c:.0f}C": {"D_H_cm2_s": d_h(t_c), "D_O2_cm2_s": d_o2(t_c), "C_O2_air_mol_l": c_o2(t_c),
                                          "D_mal_cm2_s": d_mal(t_c)} for t_c in TEMPS_C}
                        | {"delta_natural_convection_um": list(DELTA_NATURAL_CONVECTION_UM), "sources": SOURCES},
           "checks": checks, "cathode": cat, "anode": ano, "anode_check_medium": diag, "anchor_anode_sap_gap": anc,
           "not_modelled": ["which medium and convection the laboratory will use (the letter fixes neither)",
                            "the pH inside the coatings — every shift here is a lower bound at the enzyme",
                            "glucose transport at the anode",
                            "a standard laccase buffer as the cathode medium",
                            "salting-out of O2 in the 0.25 M NaCl steps of test D (raises f)",
                            "the anode at 20 °C — L4's current is a 25 °C ceiling",
                            "the anchor anode's gap state in a living stem, the pH inside its gyroid lattice and the wood "
                            "wall's own resistance (both lower its currents); migration, flow through the gap and a "
                            "CO2/HCO3- buffer (each raises them); the anchor's working current after cold start — the "
                            "EBFC's own P–V curve (HW.13)"]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
