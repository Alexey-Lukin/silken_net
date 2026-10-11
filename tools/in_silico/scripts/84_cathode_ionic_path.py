#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
84 — The ionic path anode → cathode through the tree, R_Ω, against the cold-start ceiling of R_int (00_07 HW.53, the
🤖 leg «protocol and model of R_Ω»; ⚖️ founder 2026-10-11: the bench number first, the architecture fork after it).

WHY A MODEL WHOSE ANSWER IS A REQUIREMENT. The desk pass (HW.53) found no resistivity of dead outer bark at all and
tree-path readings only in other geometries, so a model that multiplied guessed resistivities would answer its own
premises. What the tree DOES fix is geometry (canon, CEM manifests) and the budget (the ceiling of 02_03 §1.5 minus
our estimate of the electrodes' own R_int). So each element is R_k = (a material number) × (a geometric factor), the
factor is computed from the canon geometry, and the model returns for every element the material number it would
have to have to fit the budget ALONE — the bench (docs/protocols/ebfc/cathode_ionic_path_bench.md) then measures
whether it does. Literature readings are placed beside those requirements as points, never as the verdict.

THE PATH (canon: the catalytic band sits on the flange's SIDE face ABOVE the bark, ⚖️ 2026-09-18, 01_04 §3.1; the
flange rests on shallowly faced dead bark, ⚖️ 2026-10-03; PTFE-GDL covers the catalyst layer and holds its water film
in, 01_04 §5.1/§5.4 — so no liquid outside the PTFE touches the catalyst). Current leaves the anode (Zone 1) into
sapwood, reaches the living inner bark at the cambium, converges in that thin sheet toward the flange perimeter,
crosses the dead bark (rhytidome) radially, runs as a water film over the non-catalytic buffer up to the band, and
enters the catalyst layer through its LOWER EDGE only. Five elements in series:
  1. sapwood — an equipotential rod (Ø11 × L, the gyroid envelope; its pores hold sap) at depth d below the cambium,
     the living inner bark taken as a conducting plane: the rod and its mirror image, solved numerically on segments
     (thin-wire kernel). d = L_sleeve − (dead bark under the flange + inner bark). A finite trunk (r ≥ 190 mm at
     DBH 38 ≫ L) is taken as unbounded. The conducting-plane image LOWERS R1; the sheet's own resistance is element 2.
  2. living inner bark (phloem + cambial zone) — a sheet of thickness t, radial convergence from R_in to the flange
     radius r2: R2 = (ρ/t)·ln(R_in/r2)/(2π), R_in ∈ [d, d + L] — where the rod's current reaches the plane.
  3. dead outer bark (rhytidome) — radially through its thickness t_rh over an annulus at the flange perimeter of
     width w: R3 = ρ·t_rh/(2π r2 w), w ∈ [t_rh (a band as wide as the layer is thick), (r2 − r_wound) + t_rh (the
     flange footprint plus that band)].
  4. water film over the non-catalytic buffer, height h_buf, around the perimeter: R4 = R_sq·h_buf/(2π r2), R_sq =
     ρ_water/δ_film the film's sheet resistance. h_buf has NO number in canon (flange_thickness_mm is a placeholder,
     HW.8.10; the facing adds ≈ 5.2 mm at the deep edge) — bracket [1, 6.2] mm is OURS.
  5. the catalyst layer entered from its lower edge — de Levie transmission line: ionic sheet resistance of the layer
     R_sq,cl = ρ_cl·τ/(ε·δ_cl) up the band, interfacial resistance R_ct,A (Ω·m²) into it. Full-height bound (reaction
     only at the far edge): R_sq,cl·h_band/(2π r2); penetration regime: sqrt(R_sq,cl·R_ct,A)/(2π r2)·coth(h_band/λ),
     λ = sqrt(R_ct,A/R_sq,cl). Neither δ_cl, nor the electrolyte in the layer, nor R_ct,A has a number in canon.
     ⛔ This element describes the edge IF it is open to water. Canon laminates the PTFE tape onto the flange with a
     mechanical crimp around its perimeter, no adhesive (01_04 §5.3 table, «Метод фіксації»), over a catalyst layer on
     solid Ti — so in the canon's own state the lower edge is crimped too and element 5 is OPEN (R5 = ∞): the internal
     water film (01_04 §5.1) has no ionic connection to the tree at all. Canon describes no proton path to the cathode
     beyond the ORR equation (01_03 §1). The requirement printed for element 5 is what an opened edge would have to meet.

DIRECTION OF EACH CHOICE: the thinnest dead bark under the flange (`78`'s deep-edge contact) and the widest annulus
make R3 SMALL — a requirement derived there is lenient, so failing it fails every geometry; the budget takes the BEST
electrode (5 kΩ, the low end of the estimate), so it is the largest budget any reading of canon allows; the image
plane in element 1 lowers R1. Every leniency is toward «it fits» — so «does not fit» is robust, «fits» is not.

CONTROLS that can fail (raise, never warn):
  1. the segment solver reproduces the slender-rod closed form ρ(ln(2L/a) − 1)/(2πL) within 2 % at L/a = 1000;
  2. the image term vanishes far from the plane: at d = 100 L the rod-plus-image factor is within 1 % of the isolated
     rod's;
  3. the ceiling formula of 02_03 §1.5 is zero at V_OC = VIN(CS) and its printed table values come out
     (700/800 mV × typ/max → 4.0 · none · 8.0 · 4.7 kΩ to the table's rounding).

CAN show: which element can by itself exhaust the budget; what each material number must be to fit; that at the
worst-case ceiling no budget exists at all (the electrode estimate alone exceeds it). CANNOT show: a measured R_Ω
(that is the bench); a 3D current distribution (each element is a closed form with a named geometry, ±tens of %);
anything about the frozen tree beyond scaling; the cathode's own kinetics (R_ct,A is an input, not computed here).

Run:  python tools/in_silico/scripts/84_cathode_ionic_path.py      # < 1 s
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (BQ25570_PIN_CS_UW, BQ25570_VIN_CS_MAX_MV, BQ25570_VIN_CS_TYP_MV, CACHE_DIR,
                           R_INT_EBFC_EST_KOHM, R_OUTER_M, REPO_ROOT)
from lib.utils import banner

SI_DESCRIPTION = ("Series ionic resistance of the path from the anode in the sapwood to the cathode on the flange, element by "
                  "element, against the cold-start budget of the energy harvester: the material value each layer would need, "
                  "with published tree and stemflow readings beside it.")   # its row in the paper SI (72): English, no repo jargon
SCRIPTS = Path(__file__).resolve().parent
CEM = REPO_ROOT / "tools/cad/cem"
OUT = CACHE_DIR / "kinetics" / "cathode_ionic_path.json"


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S78 = _load("s78_flange_heat", "78_flange_cambium_heat.py")   # the dead bark under the flange — one home
S58 = _load("s58_install", "58_thermal_install_field.py")      # living inner bark thickness — one home

V_OC_MV = (700.0, 800.0)          # the two V_OC rows of the 02_03 §1.5 table (the Stage-2 gate is ≥ 700, 01_03 §3.5)

# Literature POINTS placed beside the requirements (desk 2026-10-11, the delegated search's queries are recorded in the
# HW.53 commit body). `read`: «full text» = read in the source by this script's author · «agent» = read by the delegated
# search, not re-read · «review» = via a review. A reading is a point, never the verdict (the bench is).
LITERATURE = [
    {"element": "1_sapwood", "quantity": "rho_ohm_m", "values": (219.0, 594.0), "species": "Pinus sylvestris",
     "what": "living sapwood, ERT in situ — the 5 % and 95 % quantiles of the sapwood's resistivity, means of nine trees",
     "conditions": "September 2006, 69–88-yr trees near Göttingen, 30 cm above ground, 8 1/3 Hz dipole-dipole",
     "source": "Bieker & Rust 2010, Silva Fennica 44(2):267–273, doi:10.14214/sf.153, p. 269", "read": "full text"},
    {"element": "1_sapwood", "quantity": "rho_ohm_m", "values": (236.5, 742.3), "species": "Pinus cembra",
     "what": "living stem, ERT in situ — the WHOLE cross-section mean, not sapwood alone",
     "conditions": "October ⊥ end of winter (March; the authors attribute the peak to frozen trunks), DBH ≈ 5–6 cm, Tyrol",
     "source": "Losso et al. 2020, Trees 34:999–1008, doi:10.1007/s00468-020-01976-x, p. 1002", "read": "full text"},
    {"element": "4_film", "quantity": "EC_uS_per_cm", "values": (136.5, 355.5), "species": "Pinus sylvestris",
     "what": "stemflow, monthly means May–August (whole summer 222.0 ± 44.35)",
     "conditions": "pole-stage stand, central Finland, summer 1974; the column unit is printed «µS» — read as µS/cm (ours)",
     "source": "Lehtonen, Westman & Kellomäki 1976, Silva Fennica 10(4):277–287, doi:10.14214/sf.a14798, Table 1 (cont.), "
               "p. 281 — a scan with no text layer, read from the page image", "read": "full text"},
    {"element": "4_film", "quantity": "film_m", "values": (0.041e-3, 0.128e-3), "species": "—",
     "what": "rain-runoff film on a VERTICAL CONCRETE wall at 1 and 10 L/(m·h) — no film on bark was found",
     "conditions": "laboratory runoff tests (Beijer 1977)",
     "source": "Beijer 1977 via Blocken, Derome & Carmeliet 2013, Build. Environ. 60:339–361, "
               "doi:10.1016/j.buildenv.2012.10.008", "read": "review (agent)"},
]
DEAD_BARK_NOTE = ("No resistivity of living rhytidome — of any species, dry or wet — was found (desk 2026-10-11). The nearest "
                  "numeric proxy is processed Quercus suber cork in air, conductivity of order 1e-12 S/m (Lança et al. 2011, "
                  "Ciência & Tecnologia dos Materiais 23(3/4):64–70, Table 2; read by the agent): a dry layer anywhere near it "
                  "is an insulator, so element 3 has a number only when wet — the bench's question.")
INNER_BARK_NOTE = ("No resistivity of living phloem in Ω·m was found; cambial-electrical-resistance readings (Shigometer, "
                   "pulsed DC) are kΩ between needles of a stated geometry, e.g. 2.1–16.6 kΩ between 4.2-cm needles 1.8 cm "
                   "apart in sweet gum (Clark et al. 1992, doi:10.48044/jauf.1992.001; read by the agent) — not converted.")
H_BUF_MM = (1.0, 6.2)             # OURS: 1 mm of non-catalytic margin … that + the ≈5.2 mm facing spread at the deep edge
N_SEG = 400                       # rod segments of the solver (control 1 holds at this N)


def ceiling_kohm(v_oc_mv: float, vin_cs_mv: float) -> float:
    """02_03 §1.5: R_int ≤ (V_OC − VIN(CS))·VIN(CS)/PIN(CS); ≤ 0 = no V_OC headroom, cold start impossible."""
    return (v_oc_mv - vin_cs_mv) * vin_cs_mv / BQ25570_PIN_CS_UW / 1000.0   # mV·mV/µW = Ω; → kΩ


def rod_factor_per_m(length_m: float, radius_m: float, depth_m: float | None, n: int = N_SEG) -> float:
    """Geometric factor G (1/m) of an equipotential rod, R = ρ·G: alone (depth None) or with its mirror image in a
    conducting plane at `depth` above its near end. Thin-wire kernel 1/sqrt(Δz² + a²), segment-integrated exactly."""
    h = length_m / n
    zc = (depth_m or 0.0) + h * (np.arange(n) + 0.5)
    lo, hi = zc - h / 2, zc + h / 2

    def p(src_lo, src_hi):   # potential at every collocation point from unit line density on every source segment
        return np.arcsinh((src_hi[None, :] - zc[:, None]) / radius_m) - np.arcsinh((src_lo[None, :] - zc[:, None]) / radius_m)

    P = p(lo, hi)
    if depth_m is not None:
        P = P - p(-hi, -lo)   # the image segment of j sits at −z_j with the opposite charge
    lam = np.linalg.solve(P, np.ones(n))
    return 1.0 / (4.0 * math.pi * lam.sum() * h)


def geometry() -> dict:
    bark = S78.bark_bracket()   # flange Ø from CEM, the deep-edge facing spread, dead bark under the flange
    zone1 = json.loads((CEM / "anchor_zone1.pine.json").read_text(encoding="utf-8"))
    sleeve = json.loads((CEM / "zone2_sleeve.json").read_text(encoding="utf-8"))
    return {"flange_radius_m": bark["flange_diameter_mm"] / 2e3, "wound_radius_m": R_OUTER_M,
            "anode_radius_m": zone1["outer_diameter_mm"] / 2e3, "anode_length_m": zone1["length_mm"] / 1e3,
            "sleeve_length_m": sleeve["length_mm"] / 1e3, "inner_bark_m": S58.T_PHLOEM / 1e3,
            "dead_bark_under_flange_m": (bark["thin_mm"] / 1e3, bark["thick_mm"] / 1e3), "bark_source": bark}


def factors(g: dict) -> dict:
    """Every element's geometric factor, as a bracket [lenient, adverse] where the geometry is a bracket."""
    r2, a, L = g["flange_radius_m"], g["anode_radius_m"], g["anode_length_m"]
    t_ph = g["inner_bark_m"]
    out = {}
    depths = [g["sleeve_length_m"] - (t + t_ph) for t in g["dead_bark_under_flange_m"]]   # thick bark → shallow anode
    out["1_sapwood_per_m"] = {"depth_below_cambium_m": depths,
                              "with_image": [rod_factor_per_m(L, a, d) for d in sorted(depths)],
                              "isolated": rod_factor_per_m(L, a, None),
                              "closed_form_isolated": (math.log(2 * L / a) - 1) / (2 * math.pi * L)}
    r_in = (min(depths), max(depths) + L)
    out["2_inner_bark_sheet"] = {"R_in_m": list(r_in), "ln_over_2pi": [math.log(r / r2) / (2 * math.pi) for r in r_in],
                                 "thickness_m": t_ph}
    t_rh = g["dead_bark_under_flange_m"]
    w = {"band": [t for t in t_rh], "footprint_plus_band": [(r2 - g["wound_radius_m"]) + t for t in t_rh]}
    out["3_dead_bark_per_m"] = {"thickness_m": list(t_rh),
                                "lenient": min(t / (2 * math.pi * r2 * ((r2 - g["wound_radius_m"]) + t)) for t in t_rh),
                                "adverse": max(t / (2 * math.pi * r2 * t) for t in t_rh), "w_m": w}
    out["4_film_per_sq"] = [h / 1e3 / (2 * math.pi * r2) for h in H_BUF_MM]
    out["5_layer_full_height_per_sq_per_m"] = 1.0 / (2 * math.pi * r2)   # × R_sq,cl × h_band
    return out


def budgets() -> list:
    rows = []
    for v in V_OC_MV:
        for label, vin in (("typ", BQ25570_VIN_CS_TYP_MV), ("max", BQ25570_VIN_CS_MAX_MV)):
            c = ceiling_kohm(v, vin)
            rows.append({"V_OC_mV": v, "VIN_CS": label, "ceiling_kohm": c,
                         "budget_best_electrode_kohm": c - R_INT_EBFC_EST_KOHM[0],
                         "budget_worst_electrode_kohm": c - R_INT_EBFC_EST_KOHM[1]})
    return rows


def requirements(f: dict, budget_ohm: float) -> dict:
    """The material number each element must have to fit `budget_ohm` ALONE, at its LENIENT geometry."""
    g1 = min(f["1_sapwood_per_m"]["with_image"])
    return {"budget_ohm": budget_ohm,
            "1_sapwood_rho_max_ohm_m": budget_ohm / g1,
            "2_inner_bark_sheet_max_ohm_sq": budget_ohm / min(f["2_inner_bark_sheet"]["ln_over_2pi"]),
            "3_dead_bark_rho_max_ohm_m": budget_ohm / f["3_dead_bark_per_m"]["lenient"],
            "4_film_sheet_max_ohm_sq": budget_ohm / min(f["4_film_per_sq"]),
            "5_layer_sheet_x_band_height_max_ohm": budget_ohm / f["5_layer_full_height_per_sq_per_m"]}


def literature_points(f: dict, budget_ohm: float) -> list:
    """Each reading turned into its element's resistance at the element's LENIENT and ADVERSE geometry, beside the budget.
    The film pairs the highest EC with the thickest film (lenient) and the lowest with the thinnest (adverse)."""
    g1 = f["1_sapwood_per_m"]["with_image"]
    film = next(r for r in LITERATURE if r["quantity"] == "film_m")["values"]
    out = []
    for r in LITERATURE:
        if r["element"] == "1_sapwood":
            lo, hi = r["values"][0] * min(g1), r["values"][1] * max(g1)
        elif r["quantity"] == "EC_uS_per_cm":
            rho = [1e4 / ec for ec in r["values"]]   # µS/cm → Ω·m
            lo = min(rho) / max(film) * min(f["4_film_per_sq"])
            hi = max(rho) / min(film) * max(f["4_film_per_sq"])
        else:
            continue   # the film thickness enters with the EC row
        out.append({**{k: r[k] for k in ("element", "species", "what", "conditions", "source", "read")},
                    "values": list(r["values"]), "quantity": r["quantity"], "element_ohm": [lo, hi],
                    "share_of_budget": [lo / budget_ohm, hi / budget_ohm]})
    return out


def controls(g: dict) -> dict:
    a = 1e-4
    L = 1000 * a
    num, cf = rod_factor_per_m(L, a, None), (math.log(2 * L / a) - 1) / (2 * math.pi * L)
    if abs(num / cf - 1) > 0.02:
        raise SystemExit(f"control 1: segment solver {num:.4g} vs closed form {cf:.4g} /m at L/a = 1000")
    La, aa = g["anode_length_m"], g["anode_radius_m"]
    far, iso = rod_factor_per_m(La, aa, 100 * La), rod_factor_per_m(La, aa, None)
    if abs(far / iso - 1) > 0.01:
        raise SystemExit(f"control 2: image at d = 100 L moves the factor by {far / iso - 1:+.3%}")
    table = {(700.0, "typ"): 4.0, (800.0, "typ"): 8.0, (800.0, "max"): 4.7}   # 02_03 §1.5 printed table
    got = {(r["V_OC_mV"], r["VIN_CS"]): r["ceiling_kohm"] for r in budgets()}
    if any(abs(got[k] - v) > 0.05 for k, v in table.items()) or got[(700.0, "max")] > 0 or ceiling_kohm(600, 600) != 0:
        raise SystemExit(f"control 3: ceilings {got} ≠ the 02_03 §1.5 table {table}")
    return {"slender_rod_solver_over_closed_form": num / cf, "image_far_over_isolated": far / iso,
            "ceiling_table_02_03": {f"{k[0]:.0f}/{k[1]}": v for k, v in got.items()}}


def main() -> int:
    banner("HW.53 — R_Ω anode → cathode through the tree: geometric factors, budget, requirements per element")
    g = geometry()
    ctl = controls(g)
    f = factors(g)
    b = budgets()
    open_budget = [r for r in b if r["budget_best_electrode_kohm"] > 0]
    req = {f"{r['V_OC_mV']:.0f}/{r['VIN_CS']}": requirements(f, r["budget_best_electrode_kohm"] * 1e3) for r in open_budget}
    f1 = f["1_sapwood_per_m"]
    print(f"  anode Ø{2e3 * g['anode_radius_m']:.0f} × {1e3 * g['anode_length_m']:.0f} mm at "
          f"{1e3 * min(f1['depth_below_cambium_m']):.1f}–{1e3 * max(f1['depth_below_cambium_m']):.1f} mm below the cambium; "
          f"G1 = {min(f1['with_image']):.2f}–{max(f1['with_image']):.2f} /m (isolated {f1['isolated']:.2f}, "
          f"closed form {f1['closed_form_isolated']:.2f})")
    for r in b:
        print(f"  V_OC {r['V_OC_mV']:.0f} mV, VIN(CS) {r['VIN_CS']}: ceiling {r['ceiling_kohm']:+.2f} kΩ → budget for R_Ω "
              f"{r['budget_best_electrode_kohm']:+.2f} (electrode 5 kΩ) / {r['budget_worst_electrode_kohm']:+.2f} kΩ (20 kΩ)")
    for k, v in req.items():
        print(f"  {k}: " + " · ".join(f"{n} ≤ {x:.3g}" for n, x in v.items() if n != "budget_ohm"))
    (budget,) = [v["budget_ohm"] for v in req.values()]
    pts = literature_points(f, budget)
    for p in pts:
        print(f"  {p['element']} {p['species']}: {p['element_ohm'][0] / 1e3:.2f}–{p['element_ohm'][1] / 1e3:.2f} kΩ "
              f"= {p['share_of_budget'][0]:.0%}–{p['share_of_budget'][1]:.0%} of the budget")
    floor = sum(min(p["element_ohm"]) for p in pts if p["species"] == "Pinus sylvestris")
    print(f"  Scots pine, sapwood + film at their most lenient: {floor / 1e3:.2f} kΩ against a budget of {budget / 1e3:.2f} kΩ")
    out = {"script": Path(__file__).name, "item": "00_07 HW.53",
           "question": "what must each layer of the anode → cathode ionic path be for R_Ω to fit the cold-start budget?",
           "geometry": g, "controls": ctl, "factors": f, "budgets": b, "requirements_alone_at_lenient_geometry": req,
           "element_5_in_canon_state": {"state": "open", "why": "the PTFE tape is laminated with a mechanical crimp around its "
                                        "perimeter over a catalyst layer on solid Ti, so its lower edge is crimped too",
                                        "homes": ["01_04 §5.3 (Метод фіксації)", "01_04 §5.1", "01_04 §5.4", "01_04 §3.1"]},
           "budget_cells_open": len(open_budget), "budget_cells": len(b),
           "literature_points": pts, "dead_bark_literature": DEAD_BARK_NOTE, "inner_bark_literature": INNER_BARK_NOTE,
           "scots_pine_sapwood_plus_film_lenient_ohm": floor,
           "scots_pine_sapwood_plus_film_lenient_exceeds_budget": bool(floor > budget)}
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
