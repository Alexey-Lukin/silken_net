#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
84 — The ionic path anode → cathode through the tree, R_Ω, against the cold-start ceiling of R_int (00_07 HW.53, the
🤖 leg «protocol and model of R_Ω»; ⚖️ founder 2026-10-11: the bench number first, the architecture fork after it).

WHY A MODEL WHOSE ANSWER IS A REQUIREMENT. The desk pass (HW.53) found no resistivity of dead outer bark at all and
tree-path readings only in other geometries, so a model that multiplied guessed resistivities would answer its own
premises. What the tree DOES fix is geometry (canon, CEM manifests); the budget is the ceiling of 02_03 §1.5 minus the
electrodes' own R_int — and THAT has no measured value in the tree (below). So each element is R_k = (a material
number) × (a geometric factor), the factor is computed from the canon geometry, and the model returns, for every
budget a canon reading allows, the material number each element would need to fit it ALONE; the bench
(docs/protocols/ebfc/cathode_ionic_path_bench.md) measures the tissue layers. Literature readings are points beside
the requirements, never the verdict.

THE ELECTRODES' OWN R_int — no instrument in the tree has measured it, and canon carries readings ×100 apart:
  • the prose estimate «5–20 kΩ» (02_03 §1.5) — born 2026-05-15 (a27783ef6) as an assumption in the cold-start
    voltage-drop arithmetic, no primary (lib.constants R_INT_EBFC_EST_KOHM);
  • the models: script 31's EIS model of the ANODE (Rs 100 Ω ASSUMED + Rct 72.9 Ω, 2 cm²) and 31b's INDICATIVE cathode
    band (Rct ≈ 0.002 Ω … 29.8 kΩ, 2 cm²) — so Rs + Rct(anode) + Rct(cathode) runs ≈ 0.17 … 30 kΩ.
  The budget is therefore printed for two readings — the model's low end (≈ 0.17 kΩ) and the prose estimate's low end
  (5 kΩ); the coin EIS of Stage 2 (00_07 HW.24) is the arbiter. A coin measured «in synthetic sap» includes its own
  electrolyte (Rs) — subtracting the path from a coin-based budget counts that Rs twice (≈ 0.1 kΩ, small).

THE PATH (canon: the catalytic band sits on the flange's SIDE face ABOVE the bark, ⚖️ 2026-09-18, 01_04 §3.1; the
flange rests on shallowly faced dead bark, ⚖️ 2026-10-03; PTFE-GDL covers the catalyst layer and holds its water film
in, 01_04 §5.1/§5.4). Current leaves the anode (Zone 1) into sapwood, reaches the living inner bark at the cambium,
converges in that thin sheet toward the flange perimeter, crosses the dead bark (rhytidome) radially, runs as a water
film over the non-catalytic buffer up to the band, and must ENTER the catalyst layer. Five elements in series:
  1. sapwood — the gyroid envelope as an equipotential cylinder (Ø11 × L; its pores hold sap) at depth d below the
     cambium, the living inner bark a conducting plane; Laplace solved by axisymmetric finite volumes (graded grid,
     V = 0 on the plane and 3 m away). d = L_sleeve − (dead bark under the flange + inner bark); L = the lattice length
     outside the sleeve: 40 mm if Zone 1 enters only by its shank (18 mm, the lock manifest), 28 mm at the PLACEHOLDER
     insertion 30 mm (Cem.cs Zone1InsertionMm, `58` L_A_INSERT) — the standing conflict 00_07 HW.26 G1. The wood is
     taken as ISOTROPIC at the ERT reading; wood conducts better along the grain, so R1 is likely an overestimate.
  2. living inner bark (phloem + cambial zone) — a sheet of thickness t, radial convergence from R_in to the flange
     radius r2: R2 = (ρ/t)·ln(R_in/r2)/(2π), R_in ∈ [d, d + L] — where the rod's current reaches the plane.
  3. dead outer bark (rhytidome) — radially through its thickness t_rh over an annulus at the flange perimeter of
     width w: R3 = ρ·t_rh/(2π r2 w), w ∈ [t_rh (a band as wide as the layer is thick), (r2 − r_wound) + t_rh (the
     flange footprint plus that band)].
  4. water film over the non-catalytic buffer, height h_buf, around the perimeter: R4 = R_sq·h_buf/(2π r2), R_sq =
     ρ_water/δ_film the film's sheet resistance. h_buf has NO number in canon (flange_thickness_mm is a placeholder,
     HW.8.10; the facing adds ≈ 5.2 mm at the deep edge) — bracket [0.5, 6.2] mm is OURS. Stemflow is one electrolyte
     the film can be; standing water in the lower-edge groove (01_04 §3.1) and sap from the bore in the pressure season
     are others, none measured.
  5. the entry into the catalyst layer — de Levie transmission line if water reaches the layer's lower edge: ionic
     sheet resistance R_sq,cl = ρ_cl·τ/(ε·δ_cl) up the band; full-height bound R_sq,cl·h_band/(2π r2). Neither δ_cl,
     nor the electrolyte in the layer, nor R_ct per area has a number in canon.
     ⚠️ Canon describes NO electrolyte path into the catalyst layer: its only electrolytes are internal (the thin film
     of 01_04 §5.1); the one fixation it names is a mechanical crimp around the PTFE's perimeter, no adhesive (01_04
     §5.3 table, «Метод фіксації»), and whether that crimp is tight — and where it sits relative to the layer — is open
     (the lamination is an open leg, 00_07 HW.25; the GDL stand treats the tape seam and crimp edge as a LEAK path). If
     the crimp seals the layer, element 5 is open (R5 = ∞) whatever the tissue path; the requirement printed for it is
     what an open edge would have to meet.

DIRECTION OF EACH CHOICE: the thinnest dead bark under the flange (`78`'s deep-edge contact) and the widest annulus
make R3 SMALL; the image plane and an isotropic ERT reading push R1 opposite ways (the plane lowers it, isotropy likely
raises it); the budget is printed at the LOW end of each R_int reading. The geometric closed forms (2–5) carry
±tens of %, so a sum within that of a budget decides nothing — the comparison is printed, not judged.

CONTROLS that can fail (raise, never warn):
  1. the finite-volume solver reproduces the exact capacitance of a sphere above a conducting plane (the sinh series)
     within 1.5 % at the control spacing — the same code path as element 1, staircase surface included;
  2. element 1 is grid-converged: halving the spacing moves G1 by < 1 %;
  3. the ceiling formula of 02_03 §1.5 is zero at V_OC = VIN(CS) and its printed table values come out
     (700/800 mV × typ/max → 4.0 · none · 8.0 · 4.7 kΩ to the table's rounding).

CAN show: what each material number must be to fit a given budget; how the budget moves with the electrodes' R_int;
where the published readings fall against both. CANNOT show: a measured R_Ω (that is the bench) or the electrodes' own
R_int (the coin); a 3D current distribution (elements 2–5 are closed forms with named geometries, ±tens of %);
anisotropic wood; whether the catalyst layer has any ionic entry at all (a construction question, 00_07 HW.53).

Run:  python tools/in_silico/scripts/84_cathode_ionic_path.py      # ~1 s
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

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (BQ25570_PIN_CS_UW, BQ25570_VIN_CS_MAX_MV, BQ25570_VIN_CS_TYP_MV, CACHE_DIR,
                           R_INT_EBFC_EST_KOHM, R_OUTER_M, REPO_ROOT)
from lib.utils import banner

SI_DESCRIPTION = ("Series ionic resistance of the path from the anode in the sapwood to the cathode on the flange, element by "
                  "element, against the cold-start budget of the energy harvester for two readings of the electrodes' own "
                  "internal resistance: the material value each layer would need, with published tree and stemflow "
                  "readings beside it.")   # its row in the paper SI (72): English, no repo jargon
SCRIPTS = Path(__file__).resolve().parent
CEM = REPO_ROOT / "tools/cad/cem"
OUT = CACHE_DIR / "kinetics" / "cathode_ionic_path.json"
EIS = CACHE_DIR / "kinetics" / "eis_model.json"            # script 31 — the anode's Rs + Rct
CATHODE_RCT = CACHE_DIR / "kinetics" / "cathode_det_rct.json"   # script 31b — the cathode's INDICATIVE Rct band


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S78 = _load("s78_flange_heat", "78_flange_cambium_heat.py")   # the dead bark under the flange — one home
S58 = _load("s58_install", "58_thermal_install_field.py")      # inner bark thickness, the Zone-1 insertion — one home

V_OC_MV = (700.0, 800.0)          # the two V_OC rows of the 02_03 §1.5 table (the Stage-2 gate is ≥ 700, 01_03 §3.5)
H_BUF_MM = (0.5, 6.2)             # OURS: 0.5 mm of non-catalytic margin … 1 mm + the ≈5.2 mm facing spread at the deep edge
H_FD_M = 0.25e-3                  # finite-volume spacing at the body; control 2 holds it to < 1 % against H_FD_M / 2
FAR_M = 3.0                       # the outer boundary (V = 0) — ≫ the anode, ≈ a 1/200 truncation of its capacitance

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
     "conditions": "October ⊥ end of winter (March; the authors: «probably» frozen trunks), DBH ≈ 5–6 cm, Tyrol",
     "source": "Losso et al. 2020, Trees 34:999–1008, doi:10.1007/s00468-020-01976-x, p. 1002", "read": "full text"},
    {"element": "4_film", "quantity": "EC_uS_per_cm", "values": (136.5, 355.5), "species": "Pinus sylvestris",
     "what": "stemflow, monthly means May–August (whole summer 222.0 ± 44.35)",
     "conditions": "pole-stage stand, central Finland, summer 1974; the column unit is printed «µS» — read as µS/cm (ours)",
     "source": "Lehtonen, Westman & Kellomäki 1976 (author order as printed on p. 277), Silva Fennica 10(4):277–287, "
               "doi:10.14214/sf.a14798, Table 1 (cont.), p. 281 — a scan with no text layer, read from the page image",
     "read": "full text"},
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


def ceiling_kohm(v_oc_mv: float, vin_cs_mv: float) -> float:
    """02_03 §1.5: R_int ≤ (V_OC − VIN(CS))·VIN(CS)/PIN(CS); ≤ 0 = no V_OC headroom, cold start impossible."""
    return (v_oc_mv - vin_cs_mv) * vin_cs_mv / BQ25570_PIN_CS_UW / 1000.0   # mV·mV/µW = Ω; → kΩ


def _graded(edges: list, h: float, far: float, growth: float = 1.08) -> np.ndarray:
    """Nodes from 0: spacing ≤ h through the last edge (every edge hit exactly), then geometric growth to `far`."""
    pts = [0.0]
    for e in edges:
        n = max(1, math.ceil((e - pts[-1]) / h - 1e-9))
        pts += list(np.linspace(pts[-1], e, n + 1)[1:])
    step = h
    while pts[-1] < far:
        step *= growth
        pts.append(pts[-1] + step)
    return np.array(pts)


def fv_factor(h: float, rod: tuple | None = None, sphere: tuple | None = None, far: float = FAR_M) -> float:
    """G (1/m), R = ρ·G, of an equipotential body in a uniform medium bounded by a conducting plane z = 0 (V = 0) and a
    far boundary (V = 0). Axisymmetric finite volumes on a graded (r, z) grid; rod = (radius, z_top, z_bottom) ·
    sphere = (radius, centre_z). Current = the flux out of the body's nodes; G = 1/current at V_body = 1, σ = 1."""
    if sphere:
        rs, zc = sphere
        r, z = _graded([rs], h, far), _graded([zc - rs, zc + rs], h, far)
    else:
        a, z0, z1 = rod
        r, z = _graded([a], h, far), _graded([z0, z1], h, far)
    nr, nz = len(r), len(z)
    R, Z = np.meshgrid(r, z, indexing="ij")
    body = ((R ** 2 + (Z - zc) ** 2) <= rs ** 2 * (1 + 1e-9)) if sphere else \
        ((R <= a * (1 + 1e-9)) & (Z >= z0 * (1 - 1e-9)) & (Z <= z1 * (1 + 1e-9)))
    fixed = body.copy()
    fixed[-1, :] = fixed[:, -1] = fixed[:, 0] = True
    val = body.astype(float).ravel()
    rf = np.concatenate([[0.0], (r[1:] + r[:-1]) / 2, [r[-1]]])
    zf = np.concatenate([[z[0]], (z[1:] + z[:-1]) / 2, [z[-1]]])
    g_r = 2 * np.pi * rf[1:-1][:, None] * np.diff(zf)[None, :] / np.diff(r)[:, None]   # links (i, j)–(i+1, j)
    g_z = (np.pi * np.diff(rf ** 2))[:, None] / np.diff(z)[None, :]                    # links (i, j)–(i, j+1)
    ii, jj = np.meshgrid(np.arange(nr), np.arange(nz), indexing="ij")
    a_ = np.concatenate([(ii[:-1] * nz + jj[:-1]).ravel(), (ii[:, :-1] * nz + jj[:, :-1]).ravel()])
    b_ = np.concatenate([(ii[1:] * nz + jj[1:]).ravel(), (ii[:, 1:] * nz + jj[:, 1:]).ravel()])
    g_ = np.concatenate([g_r.ravel(), g_z.ravel()])
    fx, bd = fixed.ravel(), body.ravel()
    k = -np.ones(nr * nz, dtype=int)
    k[~fx] = np.arange((~fx).sum())
    rows, cols, dat, rhs = [], [], [], np.zeros((~fx).sum())
    for p, q in ((a_, b_), (b_, a_)):
        m = ~fx[p]
        rows += [k[p[m]], k[p[m & ~fx[q]]]]
        cols += [k[p[m]], k[q[m & ~fx[q]]]]
        dat += [g_[m], -g_[m & ~fx[q]]]
        np.add.at(rhs, k[p[m & fx[q]]], g_[m & fx[q]] * val[q[m & fx[q]]])
    A = sp.csc_matrix((np.concatenate(dat), (np.concatenate(rows), np.concatenate(cols))), shape=(rhs.size, rhs.size))
    v = val.copy()
    v[~fx] = spla.spsolve(A, rhs)
    out, inn = bd[a_] & ~bd[b_], bd[b_] & ~bd[a_]
    current = (g_[out] * (v[a_[out]] - v[b_[out]])).sum() + (g_[inn] * (v[b_[inn]] - v[a_[inn]])).sum()
    return float(1.0 / current)


def sphere_plane_exact(radius: float, centre: float) -> float:
    """Exact G of a sphere above a conducting plane: C = 4πε·a·sinh(α)·Σ 1/sinh(nα), cosh α = centre/radius."""
    al = math.acosh(centre / radius)
    return 1.0 / (4 * math.pi * radius * math.sinh(al) * sum(1.0 / math.sinh(n * al) for n in range(1, int(700 / al))))


def geometry() -> dict:
    bark = S78.bark_bracket()   # flange Ø from CEM, the deep-edge facing spread, dead bark under the flange
    zone1 = json.loads((CEM / "anchor_zone1.pine.json").read_text(encoding="utf-8"))
    lock = json.loads((CEM / "mechanical_lock.zone1.json").read_text(encoding="utf-8"))
    sleeve = json.loads((CEM / "zone2_sleeve.json").read_text(encoding="utf-8"))
    lattice = zone1["length_mm"]
    into_bore = max(0.0, S58.L_A_INSERT - lock["shank_length_mm"])   # lattice inside the sleeve at the placeholder insertion
    return {"flange_radius_m": bark["flange_diameter_mm"] / 2e3, "wound_radius_m": R_OUTER_M,
            "anode_radius_m": zone1["outer_diameter_mm"] / 2e3,
            "anode_exposed_length_m": ((lattice - into_bore) / 1e3, lattice / 1e3),
            "zone1_insertion_placeholder_mm": S58.L_A_INSERT, "zone1_shank_mm": lock["shank_length_mm"],
            "sleeve_length_m": sleeve["length_mm"] / 1e3, "inner_bark_m": S58.T_PHLOEM / 1e3,
            "dead_bark_under_flange_m": (bark["thin_mm"] / 1e3, bark["thick_mm"] / 1e3), "bark_source": bark}


def factors(g: dict, h: float = H_FD_M) -> dict:
    """Every element's geometric factor, as a bracket where the geometry is a bracket."""
    r2, a, t_ph = g["flange_radius_m"], g["anode_radius_m"], g["inner_bark_m"]
    depths = sorted(g["sleeve_length_m"] - (t + t_ph) for t in g["dead_bark_under_flange_m"])   # thick bark → shallow
    corners = [{"depth_m": d, "length_m": L, "G_per_m": fv_factor(h, rod=(a, d, d + L))}
               for d in depths for L in g["anode_exposed_length_m"]]
    gs = [c["G_per_m"] for c in corners]
    r_in = (min(depths), max(depths) + max(g["anode_exposed_length_m"]))
    t_rh = g["dead_bark_under_flange_m"]
    return {"1_sapwood_per_m": {"corners": corners, "bracket": [min(gs), max(gs)], "depth_below_cambium_m": depths},
            "2_inner_bark_sheet": {"R_in_m": list(r_in), "thickness_m": t_ph,
                                   "ln_over_2pi": [math.log(r / r2) / (2 * math.pi) for r in r_in]},
            "3_dead_bark_per_m": {"thickness_m": list(t_rh),
                                  "lenient": min(t / (2 * math.pi * r2 * ((r2 - g["wound_radius_m"]) + t)) for t in t_rh),
                                  "adverse": 1.0 / (2 * math.pi * r2)},   # a band as wide as the layer is thick
            "4_film_per_sq": [hb / 1e3 / (2 * math.pi * r2) for hb in H_BUF_MM],
            "5_layer_full_height_per_sq_per_m": 1.0 / (2 * math.pi * r2)}   # × R_sq,cl × h_band


def electrode_readings() -> dict:
    """The electrodes' own R_int as canon carries it — low ends (kΩ); no measured value exists."""
    eis = json.loads(EIS.read_text(encoding="utf-8"))["parameters"]
    cat = json.loads(CATHODE_RCT.read_text(encoding="utf-8"))["grid"]
    model = [(eis["Rs_ohm"] + eis["Rct_ohm"] + min(c["rct_ohm"] for c in cat)) / 1e3,
             (eis["Rs_ohm"] + eis["Rct_ohm"] + max(c["rct_ohm"] for c in cat)) / 1e3]
    return {"models_31_31b_kohm": model, "prose_estimate_02_03_kohm": list(R_INT_EBFC_EST_KOHM)}


def budgets(readings: dict) -> list:
    low = {"models_31_31b": readings["models_31_31b_kohm"][0], "prose_estimate_02_03": readings["prose_estimate_02_03_kohm"][0]}
    rows = []
    for v in V_OC_MV:
        for label, vin in (("typ", BQ25570_VIN_CS_TYP_MV), ("max", BQ25570_VIN_CS_MAX_MV)):
            c = ceiling_kohm(v, vin)
            rows.append({"V_OC_mV": v, "VIN_CS": label, "ceiling_kohm": c,
                         "budget_kohm": {k: c - e for k, e in low.items()}})
    return rows


def requirements(f: dict, budget_ohm: float) -> dict:
    """The material number each element must have to fit `budget_ohm` ALONE, at its LENIENT geometry."""
    return {"budget_ohm": budget_ohm,
            "1_sapwood_rho_max_ohm_m": budget_ohm / f["1_sapwood_per_m"]["bracket"][0],
            "2_inner_bark_sheet_max_ohm_sq": budget_ohm / min(f["2_inner_bark_sheet"]["ln_over_2pi"]),
            "3_dead_bark_rho_max_ohm_m": budget_ohm / f["3_dead_bark_per_m"]["lenient"],
            "4_film_sheet_max_ohm_sq": budget_ohm / min(f["4_film_per_sq"]),
            "5_layer_sheet_x_band_height_max_ohm": budget_ohm / f["5_layer_full_height_per_sq_per_m"]}


def literature_points(f: dict) -> list:
    """Each reading turned into its element's resistance at the element's lenient and adverse geometry. The film pairs
    the highest EC with the thickest film and the lowest buffer (lenient), the opposite ends (adverse)."""
    g1 = f["1_sapwood_per_m"]["bracket"]
    film = next(r for r in LITERATURE if r["quantity"] == "film_m")["values"]
    out = []
    for r in LITERATURE:
        if r["element"] == "1_sapwood":
            lo, hi = r["values"][0] * g1[0], r["values"][1] * g1[1]
        elif r["quantity"] == "EC_uS_per_cm":
            rho = [1e4 / ec for ec in r["values"]]   # µS/cm → Ω·m
            lo = min(rho) / max(film) * min(f["4_film_per_sq"])
            hi = max(rho) / min(film) * max(f["4_film_per_sq"])
        else:
            continue   # the film thickness enters with the EC row
        out.append({**{k: r[k] for k in ("element", "species", "what", "conditions", "source", "read")},
                    "values": list(r["values"]), "quantity": r["quantity"], "element_ohm": [lo, hi]})
    return out


def controls(g: dict) -> dict:
    rs, zc = g["anode_radius_m"], 0.03
    fv, ex = fv_factor(H_FD_M / 2, sphere=(rs, zc)), sphere_plane_exact(rs, zc)
    if abs(fv / ex - 1) > 0.015:
        raise SystemExit(f"control 1: finite volumes {fv:.4f} vs the exact sphere-plane {ex:.4f} /m")
    a, L = g["anode_radius_m"], max(g["anode_exposed_length_m"])
    d = g["sleeve_length_m"] - (max(g["dead_bark_under_flange_m"]) + g["inner_bark_m"])
    coarse, fine = fv_factor(H_FD_M, rod=(a, d, d + L)), fv_factor(H_FD_M / 2, rod=(a, d, d + L))
    if abs(coarse / fine - 1) > 0.01:
        raise SystemExit(f"control 2: element 1 not grid-converged ({coarse:.4f} vs {fine:.4f} /m)")
    table = {(700.0, "typ"): 4.0, (800.0, "typ"): 8.0, (800.0, "max"): 4.7}   # 02_03 §1.5 printed table
    got = {(v, lab): ceiling_kohm(v, vin) for v in V_OC_MV
           for lab, vin in (("typ", BQ25570_VIN_CS_TYP_MV), ("max", BQ25570_VIN_CS_MAX_MV))}
    if any(abs(got[k] - v) > 0.05 for k, v in table.items()) or got[(700.0, "max")] > 0 or ceiling_kohm(600, 600) != 0:
        raise SystemExit(f"control 3: ceilings {got} ≠ the 02_03 §1.5 table {table}")
    return {"sphere_plane_fv_over_exact": fv / ex, "element_1_coarse_over_fine": coarse / fine,
            "ceiling_table_02_03": {f"{k[0]:.0f}/{k[1]}": v for k, v in got.items()}}


def main() -> int:
    banner("HW.53 — R_Ω anode → cathode through the tree: geometric factors, budgets, requirements per element")
    g = geometry()
    ctl = controls(g)
    f = factors(g)
    readings = electrode_readings()
    b = budgets(readings)
    req = {f"{r['V_OC_mV']:.0f}/{r['VIN_CS']} · {k}": requirements(f, v * 1e3)
           for r in b for k, v in r["budget_kohm"].items() if v > 0}
    pts = literature_points(f)
    pine = [p for p in pts if p["species"] == "Pinus sylvestris"]
    floor = sum(min(p["element_ohm"]) for p in pine)
    g1 = f["1_sapwood_per_m"]["bracket"]
    print(f"  anode Ø{2e3 * g['anode_radius_m']:.0f} × {1e3 * g['anode_exposed_length_m'][0]:.0f}–"
          f"{1e3 * g['anode_exposed_length_m'][1]:.0f} mm at {1e3 * min(f['1_sapwood_per_m']['depth_below_cambium_m']):.1f}–"
          f"{1e3 * max(f['1_sapwood_per_m']['depth_below_cambium_m']):.1f} mm below the cambium: G1 = {g1[0]:.2f}–{g1[1]:.2f} /m")
    print(f"  electrodes' own R_int (kΩ): models {readings['models_31_31b_kohm']} · prose estimate {readings['prose_estimate_02_03_kohm']}")
    for r in b:
        print(f"  V_OC {r['V_OC_mV']:.0f} mV, VIN(CS) {r['VIN_CS']}: ceiling {r['ceiling_kohm']:+.2f} kΩ → budget "
              + " · ".join(f"{k} {v:+.2f}" for k, v in r["budget_kohm"].items()))
    for p in pts:
        print(f"  {p['element']} {p['species']}: {p['element_ohm'][0] / 1e3:.2f}–{p['element_ohm'][1] / 1e3:.2f} kΩ")
    print(f"  Scots pine, sapwood + film at their most lenient: {floor / 1e3:.2f} kΩ")
    out = {"script": Path(__file__).name, "item": "00_07 HW.53",
           "question": "what must each layer of the anode → cathode ionic path be for R_Ω to fit the cold-start budget, "
                       "for each reading of the electrodes' own R_int canon carries?",
           "geometry": g, "controls": ctl, "factors": f, "electrode_r_int_readings": readings, "budgets": b,
           "requirements_alone_at_lenient_geometry": req, "requirements_per_kohm_of_budget": requirements(f, 1000.0),
           "literature_points": pts,
           "dead_bark_literature": DEAD_BARK_NOTE, "inner_bark_literature": INNER_BARK_NOTE,
           "scots_pine_sapwood_plus_film_lenient_ohm": floor,
           "open_budget_cells_that_hold_it": sorted(k for k, v in req.items() if v["budget_ohm"] >= floor),
           "element_5_in_canon": {"electrolyte_path_described": False,
                                  "named_fixation": "a mechanical crimp around the PTFE's perimeter, no adhesive (01_04 §5.3)",
                                  "crimp_tightness_and_position": "open — the lamination is an open leg (00_07 HW.25); the GDL "
                                                                  "stand treats the tape seam and crimp edge as a leak path"}}
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
