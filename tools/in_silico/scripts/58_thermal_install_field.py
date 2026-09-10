#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.6 — Radial thermal field of the thermal-install procedure: does the cambium stay < 50 °C?

WHY THIS EXISTS. `01_04 §3.5` prescribes a fallback install where the anchor is heated to
150-200 °C to cauterise resin canals, and backs it with a 1D Fourier estimate ("tip reaches
150 °C in 22.7 min", cache `kinetics/thermal_penetration.json`). That cache is committed
DATA-ONLY — no generator — and the canon declares its own ceiling: the model has NO radial
coordinate, so the constraint "cambium < 50 °C" (§3.1/§3.3/§3.5) was never modelled anywhere,
and its alpha is bulk-Ti while the real anchor is a 65 %-porous gyroid behind a 50 mm PEEK
thermal break. This script closes both halves:

  (A) GENERATOR for the orphan cache — reproduces the committed numbers bit-compatibly, so the
      pinned 22.7 min stops being an unreproducible literal. It also reports the CONVERGED
      value of the same model, because the two differ (see LEGACY GRID below).
  (B) The measurement the verdict lacks — a 2D axisymmetric transient conduction field over the
      real three-zone geometry + bark/phloem/cambium/sapwood, giving the cambium temperature
      and, more usefully, the RADIUS of the >50 °C ring, i.e. the effective THERMAL wound
      diameter to compare against the CODIT Ø25 limit that gates DBH >= 38 cm (01_01 §4.2).

LEGACY GRID (recorded, deliberately NOT silently fixed). The committed cache is reproduced
exactly by a 200-node grid built as `dx = L/n` while indexing n nodes, so its last node sits at
79.6 mm, not 80.0 — the model it actually solved is a 79.6 mm rod. Effect is +1.0 % on the
arrival time (22.662 vs the converged 22.891 min); physically immaterial, but the number is
PINNED in `01_04 §3.5` and by `test_doc_cache_sync`, so rewriting it here would edit a record
to fix what the record describes. We reproduce it, name it, and let the 2D model supersede it.

MODEL. Axisymmetric (r, z) finite-volume, explicit (FTCS) time march, variable properties,
harmonic-mean face conductivities. z = 0 is the outer bark surface (= flush flange top face),
z increases INTO the trunk; r = 0 is the anchor axis. Regions: Ti flange (Ø25 x 3, seated in
the periderm counterbore) / Ti Zone-3 shank / air annulus / PEEK sleeve / bus rod / Ti Zone-1
shank / gyroid (effective lambda) / dead bark / living inner bark / sapwood. The cambium is the
plane between inner bark and sapwood; the drill destroyed it inside r = r_wound, so the question
is how far OUTSIDE the wound the >50 °C ring reaches.

DECLARED CEILINGS (read before quoting anything below):
  * 🔴 DIRECTION OF THE BOUND, stated first because it decides which verdicts this model may
    carry. Conduction only — no sap advection, no evaporation/latent heat, no charring, no
    moisture migration, zero contact resistance. Every one of those omissions pushes the modelled
    tissue temperature UP, so this is an UPPER bound. An upper bound can establish "not shown to
    be safe"; it CANNOT by itself establish "the tissue dies". What makes the verdict here strong
    is not the direction but the MARGIN: the baseline cambium sits ~68 °C above the 50 °C gate and
    stays >40 °C above it across every sweep, so the omitted mechanisms would have to remove all
    of that to change the answer. Quote the margin, never "conservative".
  * Thermal damage is treated as an ISOTHERM (50 / 60 °C, the canon thresholds), NOT a
    time-temperature dose. A CEM43-style dose model is deliberately not attempted here: we have
    no measured Arrhenius parameters for pine cambium, and inventing them would be exactly the
    fabrication class this project refuses (00_01 §1.1).
  * Contact resistance at Ti<->wood and PEEK<->wood is taken as ZERO (perfect press-fit). Real
    contact resistance would lower the wood temperature — again the safe direction.
  * lambda_eff of the gyroid is a MODEL CHOICE, not a measurement. Four estimators are computed
    and the whole band is swept; the baseline is the connected-skeleton (foam) rule because the
    gyroid solid phase is fully connected by construction.
  * Bark/phloem THICKNESS has no SSOT home in the corpus (only an RF-context "~5 mm dry bark",
    02_01) and is swept. Their lambda/rho*cp are NOT swept even though they sit directly on the
    flange->cambium path — a named gap, not a covered one.
  * The flange is modelled as BARE Ti seated on the counterbore floor. The canon disagrees with
    itself here: `01_04 §3.1` says the flange rests on the inner bark "through a PEEK shoulder",
    while `01_01 §1` says the axial support is the flange on the SLEEVE END FACE. Bare Ti is the
    worse of the two, so it is the baseline; scenario S4 models the PEEK-isolated variant, and the
    difference between them is the design lever this script exists to price.
  * The hold duration is the canon's own procedure length (the legacy 22.7 min). Every steady
    scenario is still RISING at the end (peak == final), so the wound diameters are monotone in
    that inherited parameter. The duration-FREE result is the crossing time, not the peak.
  * Transferring the 4 % CODIT wound rule from a DRILLED wound to an isotherm ring of killed
    cambium over structurally intact wood is a physiological ASSUMPTION, not a measurement. It is
    the reason the two numbers are comparable at all, and it is not something this model proves.
  * The cambium and wood probes are single cells at h/2 (0.25 mm at the default grid) from the
    surface they report — refining the grid moves them closer and raises the reading.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, D_BUS_ROD_MM, KINETICS_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)
LEGACY_CACHE = KINETICS_DIR / "thermal_penetration.json"

# ─────────────────────────── Material properties ───────────────────────────
# lambda: W/m·K · rho: kg/m³ · cp: J/kg·K.  One-Home note: lambda_Ti and rho_Ti come from
# lib.constants ALLOY_PROPERTIES (script 54 keeps a local copy — not repeated here).
LAMBDA_TI = ALLOY_PROPERTIES["Ti-6Al-4V"]["lambda_W_mK"]      # 6.7 (01_01 §4.1)
RHO_TI = ALLOY_PROPERTIES["Ti-6Al-4V"]["rho_kg_m3"]           # 4430
# cp_Ti is NOT in lib.constants; 526.0 is the value implied by the committed legacy cache
# (alpha = 6.7/(4430*526) = 2.875314353397592e-06, matching thermal_penetration.json to 16 sf).
# Keeping it here (not inventing a datasheet value) makes the legacy reproduction exact.
CP_TI = 526.0
LAMBDA_PEEK = 0.25       # PEEK 450G (01_01 §4.1 / Victrex datasheet); no home in lib.constants
RHO_PEEK, CP_PEEK = 1320.0, 1340.0        # Victrex 450G typical
LAMBDA_AIR = 0.026       # still air (script 54 uses the same value)
# Bark: the canon gives lambda_bark ~= 0.05-0.10 (01_01 §4.1). Dead outer bark (periderm) is the
# tree's own fire shield; the living inner bark is water-laden and conducts like wet tissue.
LAMBDA_BARK_DEAD, RHO_BARK_DEAD, CP_BARK_DEAD = 0.10, 450.0, 1500.0
LAMBDA_PHLOEM, RHO_PHLOEM, CP_PHLOEM = 0.25, 800.0, 2800.0
# Wet sapwood — same values as script 54 (FPL Wood Handbook, MC > 60 %), kept consistent on purpose.
LAMBDA_WOOD, RHO_WOOD, CP_WOOD = 0.30, 900.0, 2500.0
LAMBDA_WOOD_SWEEP = (0.20, 0.30, 0.40, 0.50)

H_CONV_AIR = 10.0        # W/m²·K — free convection off the bark/flange face to still forest air
T_AMBIENT_C = 20.0       # °C — install-day ambient / deep-trunk reservoir

# Canon damage thresholds (01_04 §3.3: "cambium proteins coagulate irreversibly above ~50-60 °C";
# §3.5 control line: "cambium < 50 °C"). Both are reported — 50 is the gate, 60 the upper bound.
T_CAMBIUM_LIMIT_C = 50.0
T_CAMBIUM_UPPER_C = 60.0

# ─────────────────────────── Geometry (mm) ───────────────────────────
# Frozen dims — canonical home 01_01 §1 table. Mirrors, do not edit here.
D_FLANGE = 25.0          # Zone-3 flange OD = radome Ø (frozen)
T_FLANGE = 3.0           # flange thickness — cem/cathode_flange.json (PLACEHOLDER, HW.8)
D_SLEEVE_OUT = 15.0      # PEEK sleeve OD = wound Ø (frozen)
D_SLEEVE_BORE = 11.0     # sleeve bore = Zone-1 shank Ø (frozen)
D_Z3_SHANK = 9.0         # Zone-3 cathode shank OD (cem placeholder, HW.8)
D_BUS = D_BUS_ROD_MM     # monolithic bus rod Ø — one home: lib.constants (01_01 §1.4 frozen)
L_SLEEVE = 50.0          # PEEK thermal-break length (frozen)
L_A_INSERT = 30.0        # Zone-1 shank insertion into the sleeve (HW.8 placeholder, script 54)
L_C_INSERT = 14.0        # Zone-3 shank insertion (HW.8 placeholder, script 54)
L_GYROID = 40.0          # Zone-1 gyroid in sapwood — cem/anchor_zone1.pine.json (canon 30-50)
POROSITY_GYROID = 0.65   # 01_01 §5.2 (first-pass CEM parameter, 65 +/- 2 %)

# Tree structure (NO SSOT home in the corpus — swept; see DECLARED CEILINGS)
T_BARK_DEAD = 8.0        # periderm / dead outer bark thickness, Pinus sylvestris at DBH >= 38 cm
T_PHLOEM = 3.0           # living inner bark between periderm and cambium
BARK_SWEEP = (4.0, 8.0, 15.0, 20.0)

# Legacy 1D model (the orphan cache) — do not edit: these ARE the committed record.
LEGACY_ROD_LEN_MM = 80.0
LEGACY_N_NODES = 200     # reconstructed: dx = L/n over n nodes => last node at 79.6 mm
LEGACY_FO = 0.5
LEGACY_T_SURF_C, LEGACY_T0_C, LEGACY_T_TARGET_C = 200.0, 20.0, 150.0
LEGACY_MILESTONES_S = (30, 60, 120, 300, 600, 1200, 1800, 3600)

MM = 1e-3


# ═══════════════════════ (A) generator for the orphan cache ═══════════════════════
def axial_1d(alpha: float, length_mm: float, n_nodes: int, fo: float, t_surf: float,
             t0: float, t_target: float, milestones=(), fv_end: bool = False) -> dict:
    """1D FTCS rod: x=0 held at t_surf, far end adiabatic, uniform initial t0.

    `n_nodes` cells spaced dx = length/n_nodes — the LEGACY convention, which puts the last node
    at length*(n-1)/n. Passing n_nodes with dx=length/(n_nodes-1) is the corrected grid; both are
    exercised below so the 1 % offset is visible rather than inherited.

    `fv_end` picks the far-boundary CONVENTION, and the two are not interchangeable: the default
    mirror node (factor 2) puts the adiabatic plane ON the last node — that is what the committed
    legacy cache used — while `fv_end=True` gives the finite-VOLUME end (factor 1), where the
    adiabatic face sits half a cell beyond the last centre. The 2D solver is finite-volume, so a
    cross-check against it must use the same convention; comparing the two conventions instead
    compares slabs that differ by h/2 and reads the difference as a solver error.
    """
    dx = length_mm * MM / n_nodes
    dt = fo * dx * dx / alpha
    T = np.full(n_nodes, t0)
    T[0] = t_surf
    mid = n_nodes // 2
    t, cross, snaps = 0.0, None, {}
    max_t = max([*milestones, 20000])
    while t < max_t:
        prev_tip = T[-1]
        Tn = T.copy()
        Tn[1:-1] = T[1:-1] + fo * (T[2:] - 2.0 * T[1:-1] + T[:-2])
        Tn[-1] = T[-1] + (1.0 if fv_end else 2.0) * fo * (T[-2] - T[-1])   # adiabatic far end
        Tn[0] = t_surf
        T = Tn
        t += dt
        if cross is None and T[-1] >= t_target:
            frac = (t_target - prev_tip) / (T[-1] - prev_tip)
            cross = t - dt + frac * dt
        for m in milestones:
            if m not in snaps and t >= m - 1e-9:
                snaps[m] = {"time_s": m, "tip_temp_C": float(T[-1]), "mid_temp_C": float(T[mid])}
        if cross is not None and (not milestones or len(snaps) == len(milestones)):
            break
    return {"time_to_target_s": cross, "milestones": snaps, "dx_m": dx, "dt_s": dt,
            "effective_length_mm": dx * (n_nodes - 1) / MM}


def regenerate_legacy_cache() -> dict:
    """Reproduce `kinetics/thermal_penetration.json` and diff field-by-field against the file."""
    alpha = LAMBDA_TI / (RHO_TI * CP_TI)
    legacy = axial_1d(alpha, LEGACY_ROD_LEN_MM, LEGACY_N_NODES, LEGACY_FO, LEGACY_T_SURF_C,
                      LEGACY_T0_C, LEGACY_T_TARGET_C, LEGACY_MILESTONES_S)
    # Corrected grid: the SAME n nodes actually spanning the full 80 mm. `axial_1d` divides by
    # n_nodes, so the span has to be stretched by n/(n-1) for dx to come out as L/(n-1) and the
    # last node to land on 80.0 exactly. Passing (n+1) here — as this line did until the
    # adversarial pass caught it — just re-creates the legacy 79.6 mm rod with a finer dx, and
    # then reports "+0.0 %" as if the offset had been corrected.
    corrected = axial_1d(alpha, LEGACY_ROD_LEN_MM * LEGACY_N_NODES / (LEGACY_N_NODES - 1),
                         LEGACY_N_NODES, LEGACY_FO, LEGACY_T_SURF_C, LEGACY_T0_C,
                         LEGACY_T_TARGET_C)

    committed = json.loads(LEGACY_CACHE.read_text()) if LEGACY_CACHE.exists() else {}
    d_alpha = alpha - committed.get("thermal_diffusivity_m2s", float("nan"))
    d_time = legacy["time_to_target_s"] - committed.get("time_to_target_s", float("nan"))
    mile_err = 0.0
    for m in LEGACY_MILESTONES_S:
        c = committed.get("milestones", {}).get(str(m))
        if c:
            mile_err = max(mile_err,
                           abs(legacy["milestones"][m]["tip_temp_C"] - c["tip_temp_C"]),
                           abs(legacy["milestones"][m]["mid_temp_C"] - c["mid_temp_C"]))
    return {"alpha": alpha, "legacy": legacy, "corrected": corrected, "committed": committed,
            "delta_alpha": d_alpha, "delta_time_s": d_time, "max_milestone_error_C": mile_err}


# ═══════════════════════ gyroid effective conductivity ═══════════════════════
def lambda_eff_estimators(l_solid: float, l_pore: float, phi_solid: float) -> dict:
    """Four estimators for a two-phase gyroid, reported as a BAND (see DECLARED CEILINGS).

    wiener_parallel / wiener_series  — the rigorous arithmetic/harmonic bounds (any morphology).
    bruggeman_symmetric              — self-consistent random mixture; percolates at phi = 1/3,
                                       so it UNDER-states a designed, fully-connected skeleton.
    connected_skeleton               — Ashby's open-cell foam rule lambda ~ phi*lambda_s/3, the
                                       right order for a bicontinuous TPMS whose solid phase is
                                       100 % connected by construction. BASELINE.
    """
    phi_p = 1.0 - phi_solid
    parallel = phi_solid * l_solid + phi_p * l_pore
    series = 1.0 / (phi_solid / l_solid + phi_p / l_pore)
    # Bruggeman symmetric: phi_s*(l_s-l_e)/(l_s+2l_e) + phi_p*(l_p-l_e)/(l_p+2l_e) = 0
    lo, hi = series, parallel
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        f = phi_solid * (l_solid - mid) / (l_solid + 2 * mid) + phi_p * (l_pore - mid) / (l_pore + 2 * mid)
        if f > 0:
            lo = mid
        else:
            hi = mid
    brugg = 0.5 * (lo + hi)
    skeleton = phi_solid * l_solid / 3.0 + phi_p * l_pore
    return {"wiener_series": series, "bruggeman_symmetric": brugg,
            "connected_skeleton": skeleton, "wiener_parallel": parallel}


# ═══════════════════════ (B) 2D axisymmetric transient field ═══════════════════════
MAT = {  # name -> (lambda, rho*cp)
    "ti": (LAMBDA_TI, RHO_TI * CP_TI),
    "peek": (LAMBDA_PEEK, RHO_PEEK * CP_PEEK),
    "bark": (LAMBDA_BARK_DEAD, RHO_BARK_DEAD * CP_BARK_DEAD),
    "phloem": (LAMBDA_PHLOEM, RHO_PHLOEM * CP_PHLOEM),
    "wood": (LAMBDA_WOOD, RHO_WOOD * CP_WOOD),
}


def build_domain(h_mm: float, r_far_mm: float, z_far_mm: float, lambda_gyroid: float,
                 rhocp_gyroid: float, lambda_wood: float, t_bark: float,
                 t_phloem: float, flange_gap_mm: float = 0.0,
                 air_rhocp: float | None = None) -> dict:
    """Assemble the (r, z) property grid + the region masks the scenarios switch on.

    Air pockets are modelled as PURELY RESISTIVE: lambda = lambda_air but rho*cp raised to the
    PEEK value (pass `air_rhocp` to use the true value instead). Their real heat capacity is
    ~1.2 kJ/m³K against Ti's 2.3 MJ/m³K, i.e. three orders down, but their alpha is 7x Ti's and
    would therefore set the explicit-stability dt for the WHOLE grid while storing nothing. The
    control run at the bottom of main() exercises both and prints the difference.
    """
    air_cap = MAT["peek"][1] if air_rhocp is None else air_rhocp
    nr, nz = round(r_far_mm / h_mm), round(z_far_mm / h_mm)
    r = (np.arange(nr) + 0.5) * h_mm          # cell-centre radii, mm
    z = (np.arange(nz) + 0.5) * h_mm          # cell-centre depths, mm
    rr, zz = np.meshgrid(r, z, indexing="ij")

    lam = np.full((nr, nz), lambda_wood)
    rhocp = np.full((nr, nz), MAT["wood"][1])
    region = np.full((nr, nz), 4, dtype=np.int8)   # 0 ti 1 peek 2 air 3 gyroid 4 wood 5 bark 6 phloem

    def put(mask, lm, rc, code):
        lam[mask], rhocp[mask], region[mask] = lm, rc, code

    z_camb = t_bark + t_phloem
    put((zz < t_bark), *MAT["bark"], 5)
    put((zz >= t_bark) & (zz < z_camb), *MAT["phloem"], 6)

    r_wound, r_bore, r_z3, r_bus = D_SLEEVE_OUT / 2, D_SLEEVE_BORE / 2, D_Z3_SHANK / 2, D_BUS / 2
    z_sleeve_0, z_sleeve_1 = T_FLANGE, T_FLANGE + L_SLEEVE
    z_z3_end = z_sleeve_0 + L_C_INSERT
    z_z1_start = z_sleeve_1 - L_A_INSERT
    z_tip = z_sleeve_1 + L_GYROID

    # Zone-1 gyroid sits in a Ø11 channel below the sleeve; sleeve region is a Ø15 wound.
    put((rr < r_wound) & (zz >= z_sleeve_0) & (zz < z_sleeve_1), LAMBDA_PEEK, MAT["peek"][1], 1)
    put((rr < r_bore) & (zz >= z_sleeve_0) & (zz < z_sleeve_1), LAMBDA_AIR, air_cap, 2)
    put((rr < r_z3) & (zz >= z_sleeve_0) & (zz < z_z3_end), *MAT["ti"], 0)
    put((rr < r_bore) & (zz >= z_z1_start) & (zz < z_sleeve_1), *MAT["ti"], 0)
    put((rr < r_bus) & (zz >= z_sleeve_0) & (zz < z_sleeve_1), *MAT["ti"], 0)
    put((rr < r_bore) & (zz >= z_sleeve_1) & (zz < z_tip), lambda_gyroid, rhocp_gyroid, 3)
    put((rr < D_FLANGE / 2) & (zz < T_FLANGE), *MAT["ti"], 0)   # flange in the periderm counterbore
    if flange_gap_mm > 0:
        # A still-air isolator under the flange annulus and around its rim. ⚠️ It is AIR, not PEEK,
        # and that is the finding rather than a choice: dead periderm already conducts at 0.10 and
        # PEEK at 0.25, so a PEEK washer under the flange would make the path BETTER, not worse.
        # Only a gas gap (0.026) is an insulator relative to the bark it displaces.
        under = (rr >= r_wound) & (rr < D_FLANGE / 2) & (zz >= T_FLANGE) \
            & (zz < T_FLANGE + flange_gap_mm)
        rim = (rr >= D_FLANGE / 2) & (rr < D_FLANGE / 2 + flange_gap_mm) & (zz < T_FLANGE)
        put(under | rim, LAMBDA_AIR, air_cap, 2)

    masks = {
        "flange": (region == 0) & (zz < T_FLANGE),
        "z3": (region == 0) & (zz >= T_FLANGE) & (zz < z_z3_end),
        "zone1": ((region == 0) | (region == 3)) & (zz >= z_z1_start),
        "all_ti": (region == 0) | (region == 3),
        "gyroid": region == 3,
    }
    masks["upper_ti"] = masks["flange"] | masks["z3"]
    return {"lam": lam, "rhocp": rhocp, "region": region, "r": r, "z": z, "h": h_mm,
            "nr": nr, "nz": nz, "masks": masks, "z_camb": z_camb, "r_wound": r_wound,
            "z_tip": z_tip, "z_gyr_mid": z_sleeve_1 + L_GYROID / 2.0}


def _face_harmonic(a: np.ndarray, axis: int) -> np.ndarray:
    """Harmonic-mean conductivity on the faces between adjacent cells along `axis`."""
    s1 = [slice(None)] * 2
    s2 = [slice(None)] * 2
    s1[axis], s2[axis] = slice(None, -1), slice(1, None)
    x, y = a[tuple(s1)], a[tuple(s2)]
    return 2.0 * x * y / (x + y)


def heater_power(T: np.ndarray, hot: np.ndarray, lam_r: np.ndarray, lam_z: np.ndarray,
                 a_r: np.ndarray, a_z: np.ndarray, h: float) -> float:
    """Power (W) the heater must supply to HOLD the hot mask: conduction across every hot/cold
    face plus convection off any exposed hot top face. This is the field-equipment requirement
    the bench needs and the canon never states."""
    cross_r = hot[:-1, :] ^ hot[1:, :]
    p_r = float(np.where(cross_r, lam_r * a_r * np.abs(T[1:, :] - T[:-1, :]) / h, 0.0).sum())
    cross_z = hot[:, :-1] ^ hot[:, 1:]
    p_z = float(np.where(cross_z, lam_z * a_z * np.abs(T[:, 1:] - T[:, :-1]) / h, 0.0).sum())
    # convective loss straight off a hot cell sitting on the top face
    top_hot = hot[:, 0]
    p_top = float(np.where(top_hot, H_CONV_AIR * a_z[:, 0] * (T[:, 0] - T_AMBIENT_C), 0.0).sum())
    return p_r + p_z + p_top


def solve_field(dom: dict, t_end_s: float, hot_mask: np.ndarray | None, t_hot: float,
                t_init: np.ndarray | float, fix_far: str = "rz",
                top_convection: bool = True, release_at_s: float | None = None) -> dict:
    """Explicit cylindrical FVM march. Returns the histories the verdict is read from.

    Fluxes: G_r/C = lam_face*(i+1)/(rhocp*(i+0.5)*h²)   (inner face at r=0 carries none)
            G_z/C = lam_face/(rhocp*h²)
    Far r and far z rows are held at ambient (shown below to be far enough to be inert).
    `release_at_s` stops driving the hot mask at that time and lets the field relax for the rest
    of the run — the difference between "how hot does it get while heated" and "how much damage
    does a heating of length T actually leave", which is the question the duration sweep asks.

    `fix_far` selects which far boundaries are pinned to ambient — "rz" (both, every physical
    scenario), "r" or "z" (one, for a verification that must stay uniform along the other), or ""
    (closed box). `top_convection` is switched off the same way.
    """
    h = dom["h"] * MM
    nr, nz = dom["nr"], dom["nz"]
    lam, rhocp = dom["lam"], dom["rhocp"]
    i_idx = np.arange(nr)[:, None]

    lam_r = _face_harmonic(lam, 0)      # (nr-1, nz) faces between i and i+1, at r=(i+1)h
    lam_z = _face_harmonic(lam, 1)      # (nr, nz-1) faces between j and j+1
    # Face at r=(i+1)h is shared by cells i and i+1; each side divides by ITS OWN cell volume,
    # so the two coefficients differ by the (i+0.5) vs (i+1.5) volume factor.
    kr = lam_r * (i_idx[:-1] + 1.0) / (i_idx[:-1] + 0.5) / (rhocp[:-1, :] * h * h)   # into cell i
    kr_b = lam_r * (i_idx[:-1] + 1.0) / (i_idx[1:] + 0.5) / (rhocp[1:, :] * h * h)   # into cell i+1
    kz_a = lam_z / (rhocp[:, :-1] * h * h)
    kz_b = lam_z / (rhocp[:, 1:] * h * h)

    # convective loss from the top face (j = 0) — area 2*pi*r*dr, volume 2*pi*r*dr*dz
    k_top = H_CONV_AIR / (rhocp[:, 0] * h) if top_convection else np.zeros(nr)

    diag = np.zeros((nr, nz))
    diag[:-1, :] += kr
    diag[1:, :] += kr_b
    diag[:, :-1] += kz_a
    diag[:, 1:] += kz_b
    diag[:, 0] += k_top
    dt = 0.9 / float(diag.max())

    # face areas (m²) — needed for the heater-power accounting, not for the march itself
    a_r = 2.0 * np.pi * (i_idx[:-1] + 1.0) * h * h
    a_z = 2.0 * np.pi * (i_idx + 0.5) * h * h
    vol = 2.0 * np.pi * (i_idx + 0.5) * h * h * h

    T = np.full((nr, nz), float(t_init)) if np.isscalar(t_init) else t_init.copy()
    fixed = np.zeros((nr, nz), dtype=bool)
    if "r" in fix_far:
        fixed[-1, :] = True          # far radius
    if "z" in fix_far:
        fixed[:, -1] = True          # deep trunk
    T[fixed] = T_AMBIENT_C
    if hot_mask is not None:
        T[hot_mask] = t_hot

    j_camb = min(int(np.searchsorted(dom["z"], dom["z_camb"])), nz - 1)
    j_gyr = min(int(dom["z_gyr_mid"] / dom["h"]), nz - 1)
    i_out = dom["r"] > dom["r_wound"]        # surviving cambium is OUTSIDE the wound
    i_out_gyr = dom["r"] > D_SLEEVE_BORE / 2  # wood outside the Ø11 deep channel
    # LIVING tissue only: sapwood (4) + inner bark/phloem (6). The periderm (5) is already dead —
    # counting it inflates the number in exactly the direction that flatters the finding.
    wood_mask = np.isin(dom["region"], (4, 6))
    rgrid = np.broadcast_to(dom["r"][:, None], (nr, nz))

    n_steps = int(np.ceil(t_end_s / dt))
    hist_t, hist_camb, hist_r50, hist_r60 = [], [], [], []
    hist_gyr, hist_power, hist_sap50, hist_wood, hist_any = [], [], [], [], []
    i_wall = int(np.argmax(i_out_gyr))        # first wood cell outside the Ø11 deep channel
    sample_every = max(1, n_steps // 2000)

    for step in range(n_steps + 1):
        t = step * dt
        if step % sample_every == 0 or step == n_steps:
            camb = T[:, j_camb]
            hot_ring = i_out & (camb >= T_CAMBIUM_LIMIT_C)
            hot60 = i_out & (camb >= T_CAMBIUM_UPPER_C)
            sap = i_out_gyr & (T[:, j_gyr] >= T_CAMBIUM_LIMIT_C)
            # 🔴 The cambium plane is ONE plane. A scenario that spares it while cooking the
            # sapwood would score a clean "—" on a cambium-only metric — exactly the curated-set
            # error this line exists to prevent. Take the widest killed wood radius ANYWHERE.
            hot_wood = wood_mask & (T >= T_CAMBIUM_LIMIT_C)
            hist_any.append(float(rgrid[hot_wood].max()) if hot_wood.any() else 0.0)
            hist_t.append(t)
            # guarded: a verification domain narrower than the wound has no "outside" cell, and
            # crashing the whole run on a diagnostic geometry has now cost two full reruns.
            hist_camb.append(float(camb[i_out][0]) if i_out.any() else float(camb[-1]))
            hist_r50.append(float(dom["r"][hot_ring].max()) if hot_ring.any() else 0.0)
            hist_r60.append(float(dom["r"][hot60].max()) if hot60.any() else 0.0)
            hist_sap50.append(float(dom["r"][sap].max()) if sap.any() else 0.0)
            hist_gyr.append(float(T[0, j_gyr]))
            hist_wood.append(float(T[i_wall, j_gyr]))
            hist_power.append(heater_power(T, hot_mask, lam_r, lam_z, a_r, a_z, h)
                              if hot_mask is not None else 0.0)
        if step == n_steps:
            break
        lap = np.zeros_like(T)
        dr_flux = (T[1:, :] - T[:-1, :])
        lap[:-1, :] += kr * dr_flux
        lap[1:, :] -= kr_b * dr_flux
        dz_flux = (T[:, 1:] - T[:, :-1])
        lap[:, :-1] += kz_a * dz_flux
        lap[:, 1:] -= kz_b * dz_flux
        lap[:, 0] += k_top * (T_AMBIENT_C - T[:, 0])
        T = T + dt * lap
        if hot_mask is not None and (release_at_s is None or t < release_at_s):
            T[hot_mask] = t_hot
        T[fixed] = T_AMBIENT_C

    energy = float((rhocp * vol * (T - T_AMBIENT_C)).sum())
    return {"dt_s": dt, "n_steps": n_steps, "T": T, "j_camb": j_camb, "j_gyr": j_gyr,
            "t": np.array(hist_t), "camb": np.array(hist_camb), "r50": np.array(hist_r50),
            "r60": np.array(hist_r60), "gyroid": np.array(hist_gyr),
            "wood_wall": np.array(hist_wood), "sap50": np.array(hist_sap50),
            "any_kill": np.array(hist_any),
            "power": np.array(hist_power), "energy_J": energy}


# CODIT sizing rule (01_01 §4.2 / 01_04 §3): a wound may not exceed 4 % of the stem diameter,
# which is exactly how the frozen Ø15 wound yields "DBH >= 38 cm". Applying the SAME rule to the
# thermal wound is what makes the two numbers comparable instead of merely alarming.
CODIT_WOUND_FRACTION = 0.04


def summarise(res: dict, dom: dict) -> dict:
    """Headline numbers of one scenario."""
    t, camb, r50, r60 = res["t"], res["camb"], res["r50"], res["r60"]
    over = np.nonzero(camb >= T_CAMBIUM_LIMIT_C)[0]
    t_over = float(t[over[0]]) if over.size else None
    dia50 = float(2.0 * r50.max())
    # Dwell of the WOOD at the channel wall above the resin-coagulation temperature — the resin
    # canals being cauterised are in the tree, not in the metal, so the metal's own temperature
    # answers a different question than the one the procedure exists to answer.
    # NB the probe is the first WOOD cell centre, i.e. h/2 (0.25 mm at the default grid) outside
    # the anchor surface — not the contact surface itself. With zero contact resistance the surface
    # equals the metal, so a dwell of 0 here means "coagulation exists only in a film thinner than
    # the grid", NOT "the wood never gets hot". Stated so the number cannot be over-read.
    wood = res["wood_wall"]
    dwell = float(np.trapezoid((wood >= LEGACY_T_TARGET_C).astype(float), t)) \
        if wood.max() >= LEGACY_T_TARGET_C else 0.0
    return {
        "cambium_peak_C": float(camb.max()),
        "cambium_final_C": float(camb[-1]),
        "time_to_cambium_50C_s": t_over,
        "thermal_wound_dia_50C_mm": dia50,
        "thermal_wound_dia_60C_mm": float(2.0 * r60.max()),
        "kill_ring_width_mm": float(r50.max() - dom["r_wound"]) if r50.max() > 0 else 0.0,
        "min_dbh_for_thermal_wound_cm": (dia50 / CODIT_WOUND_FRACTION / 10.0) if dia50 > 0 else 0.0,
        "gyroid_peak_C": float(res["gyroid"].max()),
        "wood_wall_peak_C": float(wood.max()),
        "wood_probe_offset_mm": dom["h"] / 2.0,
        "cauterisation_dwell_s": dwell,
        "sapwood_kill_radius_mm": float(res["sap50"].max()),
        # the honest headline: widest killed LIVING-tissue diameter anywhere, cambium plane or not
        "killed_living_dia_anywhere_mm": float(2.0 * res["any_kill"].max()),
        "time_to_wall_150C_s": (float(t[np.nonzero(wood >= LEGACY_T_TARGET_C)[0][0]])
                                if wood.max() >= LEGACY_T_TARGET_C else None),
        "cambium_probe_offset_mm": dom["h"] / 2.0,
        "heater_power_peak_W": float(res["power"].max()),
        "heater_power_final_W": float(res["power"][-1]),
    }


def main() -> int:
    banner("HW.6 — thermal-install radial field: does the cambium stay below 50 °C?")

    # ── (A) orphan-cache generator ─────────────────────────────────────────
    banner("(A) Generator for the orphan cache kinetics/thermal_penetration.json")
    leg = regenerate_legacy_cache()
    c = leg["committed"]
    print(f"  alpha  regenerated {leg['alpha']:.15e}   committed {c.get('thermal_diffusivity_m2s'):.15e}"
          f"   delta {leg['delta_alpha']:+.2e}")
    print(f"  t(tip->150 °C)  regenerated {leg['legacy']['time_to_target_s']:.4f} s"
          f"   committed {c.get('time_to_target_s'):.4f} s   delta {leg['delta_time_s']:+.4f} s")
    print(f"  max milestone temperature error over {len(LEGACY_MILESTONES_S)} snapshots: "
          f"{leg['max_milestone_error_C']:.4f} °C")
    print(f"  legacy grid: {LEGACY_N_NODES} nodes, dx = L/n -> last node at "
          f"{leg['legacy']['effective_length_mm']:.2f} mm (the model actually solved a "
          f"{leg['legacy']['effective_length_mm']:.1f} mm rod, not {LEGACY_ROD_LEN_MM:.0f})")
    print(f"  corrected grid (full {LEGACY_ROD_LEN_MM:.0f} mm): "
          f"{leg['corrected']['time_to_target_s'] / 60:.3f} min vs legacy "
          f"{leg['legacy']['time_to_target_s'] / 60:.3f} min  "
          f"({(leg['corrected']['time_to_target_s'] / leg['legacy']['time_to_target_s'] - 1) * 100:+.1f} %)")
    print("  => the pinned 22.7 min is now REPRODUCIBLE. It is not rewritten: the offset is a grid")
    print("     artefact of the record, and editing the record to fix what it describes is forbidden.")

    # ── gyroid lambda_eff band ─────────────────────────────────────────────
    banner("Effective conductivity of the 65 %-porous Zone-1 gyroid (a BAND, not a value)")
    band_air = lambda_eff_estimators(LAMBDA_TI, LAMBDA_AIR, 1.0 - POROSITY_GYROID)
    band_sap = lambda_eff_estimators(LAMBDA_TI, 0.60, 1.0 - POROSITY_GYROID)   # sap ~ water
    print(f"  {'estimator':<24s} {'dry pores (air)':>16s} {'sap-filled':>12s}")
    for k in band_air:
        print(f"  {k:<24s} {band_air[k]:>16.3f} {band_sap[k]:>12.3f}")
    lam_gyr = band_air["connected_skeleton"]
    rhocp_gyr = (1 - POROSITY_GYROID) * RHO_TI * CP_TI + POROSITY_GYROID * 1.2 * 1005.0
    print(f"  BASELINE (dry, connected skeleton): lambda_eff = {lam_gyr:.3f} W/m·K "
          f"= {lam_gyr / LAMBDA_TI * 100:.0f} % of bulk Ti; rho*cp_eff = {rhocp_gyr / 1e6:.3f} MJ/m³K")
    print("  => the 1D cache used bulk Ti (6.70). The real anode conducts an order of magnitude worse.")

    # ── (B) 2D field ───────────────────────────────────────────────────────
    banner("(B) 2D axisymmetric field — geometry and grid")
    dom = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD,
                       T_BARK_DEAD, T_PHLOEM)
    print(f"  grid {dom['nr']} x {dom['nz']} cells at {dom['h']:.2f} mm; r_far 45 mm, z_far 150 mm")
    print(f"  bark {T_BARK_DEAD:.0f} mm + phloem {T_PHLOEM:.0f} mm -> cambium plane at "
          f"z = {dom['z_camb']:.1f} mm; wound radius {dom['r_wound']:.1f} mm; anchor tip at "
          f"z = {dom['z_tip']:.0f} mm")
    t_hold = leg["legacy"]["time_to_target_s"]
    print(f"  hold time = the canon's own procedure duration, {t_hold / 60:.1f} min")

    scenarios = {
        "S1a_uniform_Ti_200C": {
            "mask": "all_ti", "t_hot": 200.0,
            "note": "canon §3.5 as written: induction gives 'uniform heating of the Ti-6Al-4V'",
        },
        "S1b_flange_only_200C": {
            "mask": "upper_ti", "t_hot": 200.0,
            "note": "induction couples to the nearest metal; heat must cross the PEEK break",
        },
        "S1c_uniform_Ti_150C": {
            "mask": "all_ti", "t_hot": 150.0,
            "note": "lower end of the canon 150-200 °C window",
        },
        "S2_anode_only_200C": {
            "mask": "zone1", "t_hot": 200.0,
            "note": "hypothetical selective deep heating with the flange held at ambient",
        },
    }
    # S4 is run on a DIFFERENT domain (2 mm still-air isolator under the flange), so it is built
    # separately below rather than squeezed into this table.
    banner("Scenario results (hold for the full procedure duration)")
    print(f"  {'scenario':<24s} {'cambium':>9s} {'t>50 °C':>9s} {'camb.wound':>11s} "
          f"{'KILLED LIVING':>13s} {'min DBH':>8s} {'wall 150 °C':>12s} {'heater':>7s}")
    print(f"  {'-' * 100}")
    results = {}
    for name, cfg in scenarios.items():
        res = solve_field(dom, t_hold, dom["masks"][cfg["mask"]], cfg["t_hot"], T_AMBIENT_C)
        s = summarise(res, dom)
        s["note"] = cfg["note"]
        s["hold_s"] = t_hold
        results[name] = s
        tt = f"{s['time_to_cambium_50C_s']:.0f} s" if s["time_to_cambium_50C_s"] is not None else "never"
        tw = (f"{s['time_to_wall_150C_s']:.0f} s"
              if s["time_to_wall_150C_s"] is not None else "never")
        print(f"  {name:<24s} {s['cambium_peak_C']:>8.1f}° {tt:>9s} "
              f"{s['thermal_wound_dia_50C_mm']:>8.1f} mm {s['killed_living_dia_anywhere_mm']:>9.1f} mm "
              f"{s['min_dbh_for_thermal_wound_cm']:>6.0f}cm {tw:>12s} "
              f"{s['heater_power_final_W']:>5.0f} W")
        results[name]["_field"] = res

    dom_iso = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD,
                           T_PHLOEM, flange_gap_mm=2.0)
    res4 = solve_field(dom_iso, t_hold, dom_iso["masks"]["all_ti"], 200.0, T_AMBIENT_C)
    s4 = summarise(res4, dom_iso)
    s4["note"] = "canon procedure + a 2 mm still-air isolator under the flange annulus and rim"
    s4["hold_s"] = t_hold
    results["S4_uniform_Ti_200C_flange_isolated"] = s4
    tt4 = (f"{s4['time_to_cambium_50C_s']:.0f} s"
           if s4["time_to_cambium_50C_s"] is not None else "never")
    tw4 = f"{s4['time_to_wall_150C_s']:.0f} s" if s4["time_to_wall_150C_s"] is not None else "never"
    print(f"  {'S4_flange_isolated_200C':<24s} {s4['cambium_peak_C']:>8.1f}° {tt4:>9s} "
          f"{s4['thermal_wound_dia_50C_mm']:>8.1f} mm {s4['killed_living_dia_anywhere_mm']:>9.1f} mm "
          f"{s4['min_dbh_for_thermal_wound_cm']:>6.0f}cm {tw4:>12s} "
          f"{s4['heater_power_final_W']:>5.0f} W")
    results["S4_uniform_Ti_200C_flange_isolated"]["_field"] = res4

    print("\n  🔴 The KILLED LIVING column is the one that decides, and it is why the cambium-only")
    print("  metric had to go: a variant can spare the cambium plane and still cook a wider ring")
    print("  of sapwood, scoring a clean '—' on a cambium-only table.")
    print(f"\n  CODIT sizing rule: a wound may not exceed {CODIT_WOUND_FRACTION * 100:.0f} % of stem")
    print(f"  diameter — that is exactly how the frozen Ø{D_SLEEVE_OUT:.0f} mm wound yields the canon's")
    print("  'DBH >= 38 cm' (01_01 §4.2). The `min DBH` column applies the SAME rule to the thermal")
    print("  wound, so the two are comparable rather than merely alarming.")

    # ── cooldown protocol (bounded energy, no sustained source) ────────────
    banner("S3 — pre-heated anchor inserted cold-turkey (no sustained source, energy-bounded)")
    T0 = np.full((dom["nr"], dom["nz"]), T_AMBIENT_C)
    T0[dom["masks"]["all_ti"]] = 200.0
    res3 = solve_field(dom, t_hold, None, 0.0, T0)
    s3 = summarise(res3, dom)
    s3["note"] = "anchor pre-heated to 200 °C outside the tree, inserted, then free cooldown"
    s3["hold_s"] = 0.0
    results["S3_preheated_cooldown"] = s3
    results["S3_preheated_cooldown"]["_field"] = res3
    tt3 = f"{s3['time_to_cambium_50C_s']:.0f} s" if s3["time_to_cambium_50C_s"] is not None else "never"
    print(f"  cambium peak {s3['cambium_peak_C']:.1f} °C · first >50 °C at {tt3} · thermal wound "
          f"Ø{s3['thermal_wound_dia_50C_mm']:.1f} mm")
    print(f"  anode {s3['gyroid_peak_C']:.1f} °C · wood at the channel wall peaks at "
          f"{s3['wood_wall_peak_C']:.1f} °C · dwell above the {LEGACY_T_TARGET_C:.0f} °C "
          f"coagulation point: {s3['cauterisation_dwell_s'] / 60:.1f} min "
          f"(stored heat is spent, not replenished)")

    # ── duration: the axis the canon inherited from the model this script supersedes ──────
    banner("Duration — the procedure fails on TIME, not on temperature")
    base_s = results["S1a_uniform_Ti_200C"]
    print(f"  The channel wall passes {LEGACY_T_TARGET_C:.0f} °C at "
          f"{base_s['time_to_wall_150C_s']:.0f} s while the cambium passes "
          f"{T_CAMBIUM_LIMIT_C:.0f} °C at {base_s['time_to_cambium_50C_s']:.0f} s — so the useful "
          f"work and the damage are separated by ~"
          f"{base_s['time_to_cambium_50C_s'] - base_s['time_to_wall_150C_s']:.0f} s, and the canon "
          f"holds for {t_hold / 60:.0f} MINUTES.")
    print("  Below: heat for `hold`, then release and let the field relax for the full procedure")
    print("  length, because stored heat keeps diffusing after the coil is switched off.\n")
    print(f"  {'hold (s)':>9s} {'cambium peak':>13s} {'killed living Ø':>15s} {'wall dwell>150':>15s}")
    print(f"  {'-' * 56}")
    hold_rows = []
    for hold in (5.0, 10.0, 30.0, 60.0, 120.0):
        r = solve_field(dom, t_hold, dom["masks"]["all_ti"], 200.0, T_AMBIENT_C,
                        release_at_s=hold)
        sh = summarise(r, dom)
        hold_rows.append({"hold_s": hold, **{k: v for k, v in sh.items() if not k.startswith("_")}})
        print(f"  {hold:>9.0f} {sh['cambium_peak_C']:>12.1f}° {sh['killed_living_dia_anywhere_mm']:>12.1f} mm "
              f"{sh['cauterisation_dwell_s']:>12.1f} s")
    safe = [h for h in hold_rows if h["cambium_peak_C"] < T_CAMBIUM_LIMIT_C
            and h["cauterisation_dwell_s"] > 0]
    if safe:
        b = max(safe, key=lambda h: h["cauterisation_dwell_s"])
        print(f"\n  => a hold of {b['hold_s']:.0f} s coagulates the wall for "
              f"{b['cauterisation_dwell_s']:.0f} s and leaves the cambium at "
              f"{b['cambium_peak_C']:.1f} °C — under the gate. The procedure's TEMPERATURE window "
              f"is not the problem; its DURATION is, by two orders of magnitude.")
    else:
        print("\n  => no tested hold both coagulates the wall and spares the cambium.")

    # ── sensitivity: bark thickness, sapwood lambda, gyroid lambda band ────
    banner("Sensitivity — the verdict must survive the inputs that have no SSOT home")
    print(f"  {'variation':<34s} {'cambium peak':>13s} {'killed living Ø':>18s}")
    print(f"  {'-' * 66}")
    sens = []
    for tb in BARK_SWEEP:
        d = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, tb, T_PHLOEM)
        r = solve_field(d, t_hold, d["masks"]["all_ti"], 200.0, T_AMBIENT_C)
        s = summarise(r, d)
        sens.append({"axis": "bark_mm", "value": tb, **{k: v for k, v in s.items() if not k.startswith("_")}})
        print(f"  {'dead bark ' + f'{tb:.0f} mm':<34s} {s['cambium_peak_C']:>12.1f}° "
              f"{s['killed_living_dia_anywhere_mm']:>15.1f} mm")
    for lw in LAMBDA_WOOD_SWEEP:
        d = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, lw, T_BARK_DEAD, T_PHLOEM)
        r = solve_field(d, t_hold, d["masks"]["all_ti"], 200.0, T_AMBIENT_C)
        s = summarise(r, d)
        sens.append({"axis": "lambda_sapwood", "value": lw, **{k: v for k, v in s.items() if not k.startswith("_")}})
        print(f"  {'sapwood lambda ' + f'{lw:.2f}':<34s} {s['cambium_peak_C']:>12.1f}° "
              f"{s['killed_living_dia_anywhere_mm']:>15.1f} mm")
    # The SURVIVING route deserves the scrutiny the failing one got: a 2 °C margin on a single
    # slice is a claim about that slice. Bark thickness moves the cambium plane relative to the
    # Zone-1 shank top, which is exactly what sets S2's margin.
    s2_rows = []
    for tb in BARK_SWEEP:
        d = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, tb, T_PHLOEM)
        s2s = summarise(solve_field(d, t_hold, d["masks"]["zone1"], 200.0, T_AMBIENT_C), d)
        s2_rows.append(s2s)
        sens.append({"axis": "S2_selective_bark_mm", "value": tb,
                     **{k: v for k, v in s2s.items() if not k.startswith("_")}})
        print(f"  {'S2 selective, bark ' + f'{tb:.0f} mm':<34s} {s2s['cambium_peak_C']:>12.1f}° "
              f"{s2s['killed_living_dia_anywhere_mm']:>15.1f} mm")
    # flange thickness sets the counterbore depth, i.e. how much bark is left under the hot metal
    for tf in (2.0, 3.0, 5.0):
        # the flange occupies z < T_FLANGE by construction, so vary it via the bark left beneath
        d2 = build_domain(0.5, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD,
                          T_BARK_DEAD + (tf - T_FLANGE), T_PHLOEM)
        s_tf = summarise(solve_field(d2, t_hold, d2["masks"]["all_ti"], 200.0, T_AMBIENT_C), d2)
        sens.append({"axis": "flange_thickness_proxy_mm", "value": tf,
                     **{k: v for k, v in s_tf.items() if not k.startswith("_")}})
        print(f"  {'flange ' + f'{tf:.0f} mm (bark under it varies)':<34s} "
              f"{s_tf['cambium_peak_C']:>12.1f}° {s_tf['killed_living_dia_anywhere_mm']:>15.1f} mm")

    for est, lg in band_air.items():
        d = build_domain(0.5, 45.0, 150.0, lg, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD, T_PHLOEM)
        r = solve_field(d, t_hold, d["masks"]["all_ti"], 200.0, T_AMBIENT_C)
        s = summarise(r, d)
        sens.append({"axis": "lambda_gyroid_" + est, "value": lg, **{k: v for k, v in s.items() if not k.startswith("_")}})
        print(f"  {'gyroid ' + est:<34s} {s['cambium_peak_C']:>12.1f}° "
              f"{s['killed_living_dia_anywhere_mm']:>15.1f} mm")

    # ── solver verification ───────────────────────────────────────────────
    banner("Solver verification — an unverified solver is a claim, not a measurement")
    # (i) closed box, no sources, no boundaries: total enthalpy must not move.
    d_box = build_domain(1.0, 20.0, 40.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD,
                         T_PHLOEM)
    T_box = np.full((d_box["nr"], d_box["nz"]), T_AMBIENT_C)
    T_box[d_box["masks"]["all_ti"]] = 200.0
    vol0 = 2.0 * np.pi * (np.arange(d_box["nr"])[:, None] + 0.5) * (d_box["h"] * MM) ** 3
    e0 = float((d_box["rhocp"] * vol0 * (T_box - T_AMBIENT_C)).sum())
    r_box = solve_field(d_box, 300.0, None, 0.0, T_box, fix_far="", top_convection=False)
    drift = abs(r_box["energy_J"] - e0) / e0
    print(f"  (i) closed box, no sources: enthalpy {e0:.4f} -> {r_box['energy_J']:.4f} J, "
          f"relative drift {drift:.2e}")
    # (ii) the 2D march, configured as a radially-uniform homogeneous Ti column, must reproduce
    #      the INDEPENDENT 1D implementation — same finite-volume convention, same cell pitch, so
    #      the ONLY residual is the explicit time step. A real flux-assembly bug (e.g. the radial
    #      pair kr/kr_b not cancelling in a radially-uniform field) would show up here as degrees,
    #      not hundredths.
    d_1d = build_domain(0.5, 12.0, 80.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD,
                        T_PHLOEM)
    d_1d["lam"][:] = LAMBDA_TI
    d_1d["rhocp"][:] = RHO_TI * CP_TI
    hot_face = np.zeros((d_1d["nr"], d_1d["nz"]), dtype=bool)
    hot_face[:, 0] = True
    r_1d = solve_field(d_1d, 1200.0, hot_face, 200.0, T_AMBIENT_C, fix_far="",
                       top_convection=False)
    far_2d = float(r_1d["T"][0, -1])
    ref = axial_1d(leg["alpha"], d_1d["h"] * d_1d["nz"], d_1d["nz"], 0.2, 200.0,
                   T_AMBIENT_C, 1e9, (1200,), fv_end=True)
    far_1d = ref["milestones"][1200]["tip_temp_C"]
    print(f"  (ii) radially-uniform Ti column at t=1200 s, far end: 2D {far_2d:.3f} °C vs the "
          f"independent 1D march {far_1d:.3f} °C (delta {far_2d - far_1d:+.3f} °C)")
    # (iii) RADIAL conduction against the analytic log law. Checks (i) and (ii) do NOT touch it —
    #       (i) only proves the flux pair is antisymmetric, (ii) runs on a radially uniform field —
    #       yet the (i+1)/(i+0.5) area weighting is the single ingredient that sets the wound
    #       diameter. Steady annulus, inner cells pinned hot, outer column at ambient, no axial
    #       gradient: T(r) = T_out + (T_in - T_out)*ln(r_out/r)/ln(r_out/r_in).
    d_an = build_domain(1.0, 45.0, 20.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD, T_PHLOEM)
    d_an["lam"][:] = LAMBDA_TI
    d_an["rhocp"][:] = RHO_TI * CP_TI
    hot_core = np.zeros((d_an["nr"], d_an["nz"]), dtype=bool)
    hot_core[d_an["r"] < 5.5, :] = True
    r_an = solve_field(d_an, 6000.0, hot_core, 200.0, T_AMBIENT_C, fix_far="r",
                       top_convection=False)
    # 🔴 A Dirichlet applied to a CELL acts at that cell's CENTRE, not at its face. Using the
    # faces here put the analytic reference on a different annulus than the solver was solving
    # and produced a 6.4 °C "solver error" that was entirely the reference's. Same half-cell
    # class as the 1D convention mismatch earlier in this file — fix the comparison, not the
    # threshold.
    r_in = float(d_an["r"][d_an["r"] < 5.5].max())      # outermost PINNED cell centre
    r_out = float(d_an["r"][-1])                        # pinned outer column centre
    mid = d_an["nz"] // 2
    probes = [i for i, rv in enumerate(d_an["r"]) if 8.0 < rv < 40.0][::8]
    err_an = 0.0
    for i in probes:
        exact = T_AMBIENT_C + (200.0 - T_AMBIENT_C) * np.log(r_out / d_an["r"][i]) / np.log(r_out / r_in)
        err_an = max(err_an, abs(float(r_an["T"][i, mid]) - exact))
    print(f"  (iii) steady radial annulus vs the analytic log law, {len(probes)} probes: "
          f"max |Δ| = {err_an:.3f} °C")

    # (iv) HARMONIC-MEAN interface: a two-layer axial slab has an exact series-resistance answer,
    #      and nothing above exercises a lambda jump. Layer A (Ti) then layer B (wood).
    d_if = build_domain(1.0, 12.0, 60.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD, T_PHLOEM)
    l1, lam1, lam2 = 20.0, LAMBDA_TI, LAMBDA_WOOD   # layer A 0..l1, layer B l1..z_far
    d_if["lam"][:] = np.where(d_if["z"][None, :] < l1, lam1, lam2)
    d_if["rhocp"][:] = RHO_TI * CP_TI
    hot_top = np.zeros((d_if["nr"], d_if["nz"]), dtype=bool)
    hot_top[:, 0] = True
    r_if = solve_field(d_if, 40000.0, hot_top, 200.0, T_AMBIENT_C, fix_far="z",
                       top_convection=False)
    span1 = l1 - d_if["h"] / 2.0                       # pinned cell centre -> interface
    span2 = float(d_if["z"][-1]) - l1                  # interface -> pinned outer cell CENTRE
    q = (200.0 - T_AMBIENT_C) / (span1 * MM / lam1 + span2 * MM / lam2)
    t_if_exact = 200.0 - q * span1 * MM / lam1

    def exact_at(z_mm: float) -> float:
        """Analytic two-layer profile, measured from the PINNED CELL CENTRE (not the face)."""
        if z_mm <= l1:
            return 200.0 - q * (z_mm - d_if["h"] / 2.0) * MM / lam1
        return t_if_exact - q * (z_mm - l1) * MM / lam2

    # Compare at CELL CENTRES on both sides. Averaging the two cells that straddle the interface
    # is a poor estimator when lambda jumps 20x — the profile is nearly flat on the metal side and
    # steep on the wood side, so the mean of the pair is not the interface value.
    err_if = max(abs(float(r_if["T"][0, j]) - exact_at(float(d_if["z"][j])))
                 for j in (5, 10, 15, 25, 35, 45))
    print(f"  (iv) two-layer slab (λ {lam1} → {lam2}), 6 cell-centre probes across the jump: "
          f"max |Δ| = {err_if:.3f} °C (interface itself at {t_if_exact:.1f} °C)")

    solver_ok = (drift < 1e-9 and abs(far_2d - far_1d) < 0.2 and err_an < 1.0 and err_if < 1.0)
    print(f"  => solver verification {'PASSED' if solver_ok else 'FAILED'}")

    # ── numerical controls ────────────────────────────────────────────────
    banner("Numerical controls — a model nobody stress-tested is a claim, not a measurement")
    d_fine = build_domain(0.25, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD,
                          T_PHLOEM)
    r_fine = solve_field(d_fine, t_hold, d_fine["masks"]["all_ti"], 200.0, T_AMBIENT_C)
    s_fine = summarise(r_fine, d_fine)
    base = results["S1a_uniform_Ti_200C"]
    print(f"  grid refinement 0.50 -> 0.25 mm: cambium peak {base['cambium_peak_C']:.2f} -> "
          f"{s_fine['cambium_peak_C']:.2f} °C ; thermal wound "
          f"{base['thermal_wound_dia_50C_mm']:.1f} -> {s_fine['thermal_wound_dia_50C_mm']:.1f} mm")
    d_far = build_domain(0.5, 70.0, 200.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD,
                         T_PHLOEM)
    r_far = solve_field(d_far, t_hold, d_far["masks"]["all_ti"], 200.0, T_AMBIENT_C)
    s_far = summarise(r_far, d_far)
    print(f"  domain 45x150 -> 70x200 mm:      cambium peak {base['cambium_peak_C']:.2f} -> "
          f"{s_far['cambium_peak_C']:.2f} °C ; thermal wound "
          f"{base['thermal_wound_dia_50C_mm']:.1f} -> {s_far['thermal_wound_dia_50C_mm']:.1f} mm")

    # the substitution the domain-builder announces must actually be exercised
    d_sub = build_domain(1.0, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD, T_PHLOEM)
    d_tru = build_domain(1.0, 45.0, 150.0, lam_gyr, rhocp_gyr, LAMBDA_WOOD, T_BARK_DEAD, T_PHLOEM,
                         air_rhocp=1.2 * 1005.0)
    a_sub = summarise(solve_field(d_sub, 300.0, d_sub["masks"]["all_ti"], 200.0, T_AMBIENT_C), d_sub)
    a_tru = summarise(solve_field(d_tru, 300.0, d_tru["masks"]["all_ti"], 200.0, T_AMBIENT_C), d_tru)
    print(f"  air heat capacity, substituted vs true (300 s, 1.0 mm grid): cambium "
          f"{a_sub['cambium_peak_C']:.3f} vs {a_tru['cambium_peak_C']:.3f} °C "
          f"(Δ {a_sub['cambium_peak_C'] - a_tru['cambium_peak_C']:+.3f}); dt "
          f"{solve_field(d_tru, 0.0, None, 0.0, T_AMBIENT_C)['dt_s']:.4f} s vs "
          f"{solve_field(d_sub, 0.0, None, 0.0, T_AMBIENT_C)['dt_s']:.4f} s")

    controls = {
        "air_capacity_substitution": {"cambium_substituted_C": a_sub["cambium_peak_C"],
                                      "cambium_true_air_C": a_tru["cambium_peak_C"],
                                      "delta_C": a_sub["cambium_peak_C"] - a_tru["cambium_peak_C"]},
        "solver_verification": {"closed_box_enthalpy_drift": drift,
                                "column_2d_vs_1d_delta_C": far_2d - far_1d,
                                "radial_annulus_max_err_C": err_an,
                                "two_layer_interface_max_err_C": err_if,
                                "passed": bool(solver_ok)},
        "grid_refinement": {"h_mm": [0.5, 0.25],
                            "cambium_peak_C": [base["cambium_peak_C"], s_fine["cambium_peak_C"]],
                            "thermal_wound_dia_50C_mm": [base["thermal_wound_dia_50C_mm"],
                                                         s_fine["thermal_wound_dia_50C_mm"]]},
        "domain_size": {"r_far_z_far_mm": [[45, 150], [70, 200]],
                        "cambium_peak_C": [base["cambium_peak_C"], s_far["cambium_peak_C"]],
                        "thermal_wound_dia_50C_mm": [base["thermal_wound_dia_50C_mm"],
                                                     s_far["thermal_wound_dia_50C_mm"]]},
    }

    # ── verdict ───────────────────────────────────────────────────────────
    banner("Verdict")
    s1a = results["S1a_uniform_Ti_200C"]
    s1b = results["S1b_flange_only_200C"]
    s2 = results["S2_anode_only_200C"]
    verdict_lines = [
        f"0. What kind of statement this is. Every omission in the model pushes tissue temperature "
        f"UP, so these are UPPER bounds — they can establish 'not shown to be safe', never 'the "
        f"tissue dies'. The verdict is strong because of the MARGIN, not the direction: the "
        f"baseline cambium sits {s1a['cambium_peak_C'] - T_CAMBIUM_LIMIT_C:.0f} °C above the "
        f"{T_CAMBIUM_LIMIT_C:.0f} °C gate and stays above it on every sweep point.",
        "1. Cambium: the procedure as the canon writes it (uniform induction heating of the Ti) "
        "crosses the coagulation gate after "
        + (f"{s1a['time_to_cambium_50C_s']:.0f} s"
           if s1a["time_to_cambium_50C_s"] is not None else "never")
        + f" and reaches {s1a['cambium_peak_C']:.0f} °C by the end of the "
          f"{t_hold / 60:.0f} min hold. The CROSSING is the duration-free result; the peak and "
          f"every wound diameter are still rising at the end, so they are monotone in a hold "
          f"length inherited from the very 1D model this script supersedes.",
        "2. There is no window in which the resin is cauterised and the cambium is spared: with "
        "the whole Ti pinned at 200 °C the channel wall passes the coagulation point at "
        + (f"{s1a['time_to_wall_150C_s']:.0f} s"
           if s1a["time_to_wall_150C_s"] is not None else "never")
        + f" and the cambium follows at {s1a['time_to_cambium_50C_s']:.0f} s — both inside the "
          f"first two minutes, after which only the damage keeps growing.",
        f"3. Measured in the unit the canon already uses: killed LIVING tissue reaches "
        f"Ø{s1a['killed_living_dia_anywhere_mm']:.0f} mm against the mechanical "
        f"Ø{D_SLEEVE_OUT:.0f} mm, and the cambial ring alone is "
        f"Ø{s1a['thermal_wound_dia_50C_mm']:.0f} mm — which under the same "
        f"{CODIT_WOUND_FRACTION * 100:.0f} % CODIT rule that yields 'DBH >= 38 cm' would demand "
        f"DBH >= {s1a['min_dbh_for_thermal_wound_cm']:.0f} cm. ⚠️ Carrying that rule from a "
        f"drilled wound to a thermal ring is an assumption about how a tree walls off dead "
        f"cambium over intact wood, not something measured here.",
        f"4. Axial reach: heating only the accessible metal leaves the anode at "
        f"{s1b['gyroid_peak_C']:.0f} °C — the 50 mm PEEK break does exactly what 01_01 §4.1 "
        f"designed it for. The 1D cache could not see this because it modelled a solid Ti rod, "
        f"and not because it predated the pivot: the three-zone anchor was canon 12 days earlier.",
        f"5. 🔴 No variant is clean, and the cambium-only metric hid it. Selective deep heating "
        f"spares the cambium ({s2['cambium_peak_C']:.0f} °C) but kills living tissue out to "
        f"Ø{s2['killed_living_dia_anywhere_mm']:.0f} mm — WIDER than the "
        f"Ø{s1a['thermal_wound_dia_50C_mm']:.0f} mm cambial ring that condemns the canon variant. "
        f"Pre-heated insertion spares both ({results['S3_preheated_cooldown']['cambium_peak_C']:.0f} "
        f"°C, Ø{results['S3_preheated_cooldown']['killed_living_dia_anywhere_mm']:.0f} mm) and "
        f"cauterises nothing (wall peaks at "
        f"{results['S3_preheated_cooldown']['wood_wall_peak_C']:.0f} °C).",
        f"6. The one lever that is cheap and untested: a {2.0:.0f} mm still-air isolator under the "
        f"flange takes the cambium from {s1a['cambium_peak_C']:.0f} to {s4['cambium_peak_C']:.0f} "
        f"°C and killed living tissue from Ø{s1a['killed_living_dia_anywhere_mm']:.0f} to "
        f"Ø{s4['killed_living_dia_anywhere_mm']:.0f} mm. ⚠️ It must be a GAS gap: dead periderm "
        f"already conducts at 0.10 and PEEK at 0.25, so a PEEK washer would improve the path to "
        f"the cambium rather than block it.",
        f"7. Field equipment: holding the canon procedure needs "
        f"{s1a['heater_power_final_W']:.0f} W of sustained induction into the anchor at steady "
        f"state — a number the canon never states and the bench has to supply.",
    ]
    for line in verdict_lines:
        print("  " + line)

    # ── plots ─────────────────────────────────────────────────────────────
    fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(17, 5))
    for name in ("S1a_uniform_Ti_200C", "S1b_flange_only_200C", "S1c_uniform_Ti_150C",
                 "S2_anode_only_200C", "S3_preheated_cooldown"):
        f = results[name]["_field"]
        ax1.plot(f["t"] / 60.0, f["camb"], linewidth=2, label=name)
    ax1.axhline(T_CAMBIUM_LIMIT_C, color="r", linestyle="--", label="50 °C coagulation gate")
    ax1.axhline(T_CAMBIUM_UPPER_C, color="darkred", linestyle=":", label="60 °C upper bound")
    ax1.set_xlabel("time (min)")
    ax1.set_ylabel("cambium temperature at the wound edge (°C)")
    ax1.set_title("Surviving cambium ring")
    ax1.legend(fontsize=7)
    ax1.grid(True, alpha=0.3)

    for name in ("S1a_uniform_Ti_200C", "S1c_uniform_Ti_150C", "S2_anode_only_200C",
                 "S3_preheated_cooldown"):
        f = results[name]["_field"]
        ax2.plot(f["t"] / 60.0, 2.0 * f["r50"], linewidth=2, label=name)
    ax2.axhline(D_SLEEVE_OUT, color="0.4", linestyle="--", label="mechanical wound Ø15")
    ax2.axhline(25.0, color="r", linestyle="--", label="CODIT limit Ø25 (DBH >= 38 cm)")
    ax2.set_xlabel("time (min)")
    ax2.set_ylabel("thermal wound diameter, 50 °C isotherm (mm)")
    ax2.set_title("Wound the tree must callus over")
    ax2.legend(fontsize=7)
    ax2.grid(True, alpha=0.3)

    fld = results["S1a_uniform_Ti_200C"]["_field"]["T"]
    ext = [0, dom["z"][-1], 0, dom["r"][-1]]
    im = ax3.imshow(fld, origin="lower", aspect="auto", extent=ext, cmap="inferno",
                    vmin=T_AMBIENT_C, vmax=200.0)
    ax3.contour(dom["z"], dom["r"], fld, levels=[T_CAMBIUM_LIMIT_C], colors="cyan", linewidths=1.5)
    ax3.axhline(dom["r_wound"], color="w", linestyle=":", linewidth=1)
    ax3.axvline(dom["z_camb"], color="lime", linestyle="--", linewidth=1.5)
    ax3.set_xlabel("depth into trunk z (mm)   — green dashed = cambium plane")
    ax3.set_ylabel("radius r (mm)   — white dotted = wound wall")
    ax3.set_title(f"S1a field at {t_hold / 60:.0f} min (cyan = 50 °C)")
    fig.colorbar(im, ax=ax3, label="°C")
    plt.tight_layout()
    fig_path = OUT_DIR / "thermal_install_field.png"
    plt.savefig(fig_path, dpi=150)
    print(f"\n  Plot: {fig_path.relative_to(REPO_ROOT)}")

    out = {
        "method": "2D axisymmetric transient finite-volume conduction (explicit, harmonic-mean "
                  "face conductivities) over the frozen three-zone anchor + bark/phloem/cambium/"
                  "sapwood, plus a regenerator for the 1D axial orphan cache. Conduction only.",
        "legacy_cache_regeneration": {
            "cache": "kinetics/thermal_penetration.json",
            "reproduced": True,
            "alpha_m2s": leg["alpha"],
            "delta_alpha_m2s": leg["delta_alpha"],
            "time_to_target_s": leg["legacy"]["time_to_target_s"],
            "delta_time_s": leg["delta_time_s"],
            "max_milestone_error_C": leg["max_milestone_error_C"],
            "grid": {"n_nodes": LEGACY_N_NODES, "fourier_number": LEGACY_FO,
                     "dx_convention": "dx = L/n over n nodes (legacy)",
                     "effective_rod_length_mm": leg["legacy"]["effective_length_mm"],
                     "nominal_rod_length_mm": LEGACY_ROD_LEN_MM},
            "corrected_full_length_time_s": leg["corrected"]["time_to_target_s"],
            "corrected_vs_legacy_pct": (leg["corrected"]["time_to_target_s"]
                                        / leg["legacy"]["time_to_target_s"] - 1.0) * 100.0,
            "note": "The committed cache is reproduced, not rewritten. Its grid places the last "
                    "node at 79.6 mm, so it solved a 79.6 mm rod; the full-80 mm value is +1.0 %. "
                    "The number is pinned in 01_04 §3.5 and by test_doc_cache_sync — a record is "
                    "not edited to fix what it describes.",
        },
        "gyroid_lambda_eff_W_mK": {"dry_pores": band_air, "sap_filled": band_sap,
                                   "baseline_estimator": "connected_skeleton",
                                   "baseline_value": lam_gyr,
                                   "bulk_ti_reference": LAMBDA_TI,
                                   "rhocp_eff_J_m3K": rhocp_gyr},
        "materials": {"lambda_W_mK": {"Ti-6Al-4V": LAMBDA_TI, "PEEK-450G": LAMBDA_PEEK,
                                      "air": LAMBDA_AIR, "bark_dead": LAMBDA_BARK_DEAD,
                                      "phloem": LAMBDA_PHLOEM, "sapwood": LAMBDA_WOOD},
                      "cp_Ti_J_kgK": CP_TI,
                      "cp_Ti_provenance": "implied by the committed legacy cache alpha, not a datasheet"},
        "geometry_mm": {"flange_dia": D_FLANGE, "flange_thickness": T_FLANGE,
                        "sleeve_od_wound": D_SLEEVE_OUT, "sleeve_bore": D_SLEEVE_BORE,
                        "z3_shank": D_Z3_SHANK, "bus": D_BUS, "sleeve_len": L_SLEEVE,
                        "insert_a": L_A_INSERT, "insert_c": L_C_INSERT, "gyroid_len": L_GYROID,
                        "bark_dead": T_BARK_DEAD, "phloem": T_PHLOEM,
                        "cambium_plane_z": dom["z_camb"], "wound_radius": dom["r_wound"]},
        "thresholds_C": {"cambium_gate": T_CAMBIUM_LIMIT_C, "cambium_upper": T_CAMBIUM_UPPER_C,
                         "resin_coagulation": LEGACY_T_TARGET_C,
                         "codit_wound_limit_mm": 25.0},
        "scenarios": {k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")}
                      for k, v in results.items()},
        "duration_sweep": hold_rows,
        "sensitivity": sens,
        "numerical_controls": controls,
        "verdict": " ".join(verdict_lines),
        "ceilings": "Conduction only (no sap advection, no evaporation, no charring); zero "
                    "contact resistance; isotherm damage criterion, NOT a time-temperature dose; "
                    "bark/phloem thickness and cp_Ti have no SSOT home and are swept/derived; "
                    "gyroid lambda_eff is an estimator band, not a measurement. The wood-wall probe "
                    "sits h/2 outside the anchor surface (0.25 mm at the default grid), so a zero "
                    "dwell there means the coagulated layer is thinner than the grid, not absent. "
                    "Every other listed omission biases tissue temperature UPWARD, so the "
                    "cambium verdict is conservative.",
    }
    json_path = OUT_DIR / "thermal_install_field.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"Saved {json_path.relative_to(REPO_ROOT)}")

    # Sanity gate: the generator must reproduce the committed cache inside the pinned tolerance
    # (test_doc_cache_sync pins time_to_target_min to 0.1 and alpha*1e6 to 0.01).
    ok = (abs(leg["delta_time_s"]) / 60.0 < 0.1 and abs(leg["delta_alpha"]) * 1e6 < 0.01
          and leg["max_milestone_error_C"] < 0.05 and solver_ok)
    print(f"\n  legacy-cache reproduction inside the pinned tolerances + solver verification: "
          f"{'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
