#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""108 — `106`'s bonded gyroid interface read as a contact pressed by a growth pressure and held by friction: the exact
interface traction split into its normal and shear parts, the friction the bonded field needs, where the interface
opens and the growth pressure NEEDED to keep it closed — a lower bound on a smooth envelope, a demand elsewhere,
never a pressure that keeps it closed (00_07 HW.23, the leg «межа гіроїд ⊥ тканина ⊥ стара деревина
в `106` — засновок ідеального зчеплення НЕ ПІДТРИМАНИЙ…», step (1): a validity map, no new mechanics).

WHY. `106` computes the share t_L of the wood's strain the gyroid takes on a PERFECTLY BONDED interface, and no primary in
reach supports a bond between the callus and the gyroid or measures one (SUMMARY §«How Much of the Wood's Strain the
Bonded Gyroid Takes»). Testing that premise needs no new solution: on the bonded solution the interface traction is
EXACT, so ask what a contact WITHOUT adhesion — pressed by a growth pressure p₀ and held by Coulomb friction — would need
in order to carry the same field.

MODEL — `106`'s solution, re-read (in-silico §When Modifying #4). The gyroid: an infinite circular cylinder along R (the
stem's radius), its section in the L–T plane, bonded in an infinite orthotropic matrix under the stem's remote bending
stress σ_L. Its stress σᴵ = Cᴵ:εᴵ is UNIFORM. `106`'s cache carries no σᴵ, so it is recomputed here with `106`'s own
functions (importlib, never its main()); the inclusion tensor's composition — a closure inside `106`'s main() — is
rewritten line for line and held, before use, to every cell of EVERY group `106` caches (the Scots pine group ⊥ the
green Pinaceae group, ⚖️ (Б) 2026-10-22; four share fields and two angles per cell). A `106` group or cell block this
script does not read is a refusal, not a skip. σᴵ is taken per unit remote strain along L (ε^∞_LL = σ_L/E_L on every
reading). On the interface, at the angle ψ from L toward T (ψ is the point on the circle — `106`'s θ is the cube's
install rotation), n = (cos ψ, sin ψ, 0) and t(ψ) = σᴵ·n splits into
  σ_n = n·σᴵ·n (TENSION POSITIVE) · τ_ψ = e_ψ·σᴵ·n (in-plane, around the circle) · τ_R = e_R·σᴵ·n (axial, along R).
The loading produces σ_n and τ_ψ only: the wood (orthotropic, R a principal axis), the lattice (cubic, rotated about R),
the Voigt phase bound and σ_L are all even under R → −R, so σᴵ_LR = σᴵ_TR = 0 and τ_R ≡ 0 (asserted on every state). In
the plane the traction runs the Mohr circle of σᴵ: σ_n = c + r·cos 2(ψ − ψ₁), τ_ψ = −r·sin 2(ψ − ψ₁) (c the centre,
r the radius, σ₁ = c + r, σ₂ = c − r, ψ₁ the σ₁ direction).
  The contact. A uniform normal pressure p₀ — a READING: uniform, sustained, with no shear of its own — superposed on the
sway's bonded field, which is the contact's field exactly as long as it sticks and stays closed everywhere; that is what
the map tests. Contact pressure p₀ − σ_n; OPENING where σ_n ≥ p₀; where closed, the friction needed
μ_req(ψ) = |τ(ψ)|/(p₀ − σ_n(ψ)). Its maximum over the circle is the tangent from the origin to the shifted Mohr circle,
μ_max = ε·r/√(P² − (ε·r)²), P = p₀ − s·ε·c, with s = +1 when the wood at the anchor is in TENSION (the anchor on the
stem's windward, convex face) and −1 in COMPRESSION (leeward) — both halves occur as the wind turns. The tension half
opens first at ψ₁ (at θ = 0: the poles facing along the stem) above ε = p₀/σ₁, the compression half at ψ₁ + 90° (the
poles facing around the stem) above ε = p₀/(−σ₂) when σ₂ < 0; the averaged traction opens a share arccos(κ)/π of the
circumference, κ = (p₀/ε − s·c)/r. μ_max and the open share rise with ε (shown in the docstring of `half_map`). μ is NOT
picked and p₀ is NOT picked: the map prints the friction needed and the growth pressure each statement NEEDS — ε·σ₁ to
keep the tension half closed (ε·(−σ₂) in compression) — and sets the named readings beside it.
  ⚠️ WHAT THE TRACTION IS. It is the HOMOGENISED traction on the gyroid's envelope — the average over the cut lattice —
and on the Ø11 envelope a lattice cell (the CEM's period, rim to core) spans 21–26° of ψ, so the ψ-resolved open shares
and μ maxima carry an unquantified O(cell/radius) error (`psi_resolution` in the cache, built from the CEM). Its
DIRECTION holds only for a SMOOTH contact whose local normal is the envelope's n: there full stick needs
|τ_loc| ≤ μ·p_loc at every point, which integrates to |τ̄| ≤ μ·p̄, so μ_req of the averages is a lower bound on the
friction that contact needs and an averaged σ̄_n ≥ p₀ forces an opening somewhere — such a contact can be shown failing,
never holding. A contact that is not smooth has NO guaranteed direction: an inclined facet carries averaged shear with
zero friction (|τ̄|/p̄ = tan α), an undercut facet carries averaged tension under positive local pressure. Canon puts the
callus INTO the macropores (01_04 §2, Phase 2) — an interlock with the lattice, whose envelope is then no contact
surface: there the envelope traction is the DEMAND on the interlocked composite, and neither failing nor holding follows
from it. Even the bare-lattice cells are a smooth envelope only while no tissue grows into the surface relief. On a Voigt
cell σᴵ is the stress of a bound tensor, which breaks traction continuity at the internal Ti–tissue faces: it is not
the average of any admissible local traction field. So the smooth-contact statements — an opening, a friction lower
bound — are taken over the BARE-lattice cells only (`summary_bare_lattice`); on the additive and Voigt cells, which
put tissue in the pores, the same numbers are the demand (the 2026-10-22 review, finding 3). Field names say «opens»
for the averaged traction reaching p₀ on every cell; on a cell with tissue in the pores that is a demand, not an opening.
  p₀. No primary found in reach (2026-10-22) measures a stem callus' growth pressure on an inclusion, so p₀ takes NAMED
readings of ROOT growth pressure in one primary, Bruder 1998 (FZKA 6206, doi 10.5445/IR/67698), as the leg allows
(00_07 HW.23 step (1)): 0.72 MPa — his own first field test, 15 spring clamps (5, 10 and 20 N/mm) on thin poplar roots
(< 10 mm), read after about 2 years at about 2 mm of thickness growth («Dickenzuwachs» — a diameter for a root), the
largest over the clamps («bis zu»; p. 100); a
spring clamp is a compliant restraint, so the reading is no stall pressure against rigid titanium, and Bruder left open
whether it rises further — and the turgor of free root cells, about 0.5 MPa (p. 15, his ref [27]; p. 100 repeats it),
secondary. ⛔ 2.5 MPa is NOT taken: Bruder uses it twice in two senses — p. 15 «bis 2,5 MPa und darüber» (roots impeded in
their expansion, measured indirectly, his ref [28], open-ended above) and p. 100 the soil strength at which root growth
stops, «2,5 MPa angegeben [86]» (his ref [86], cross-referenced to the p. 15 section) — so it is ambiguous, and it is
printed only as the excluded value. The further root figures on p. 100–101 (primary growth near the root tip, ref [85];
a bottle-neck root, ref [87]) are not taken by the leg; they are listed in the cache beside the readings.
  Scale: the source day's stem strain `105` carries from `87` (one Scots pine, DBH 21.5 cm, one January day: the median
and the upper whisker of the tilt), at the gyroid through `105`'s depth fractions — r/R → 1 (a large stem, `106`'s
binding cell) and a DBH-38 host's gyroid with the strain on its bark (`105`'s junction): the two ends of the source day
at the gyroid are its median on the DBH-38 bark and its upper whisker on a large stem.
  Axial. The infinite cylinder's τ_R is zero, but the same interface carries the anode's axial bond force (`105`'s S2
path, read from `105`'s cache) — its mean over the envelope (the CEM's Ø × length) is printed for scale only. It is not
superposed point by point (its distribution along the gyroid is a shear lag no script computes) and never paired with a
`106` cell (`105`'s bond states are not `106`'s cells — in-silico §When Modifying #45 ⊕). Its effect on the friction
needed has NO direction here: it adds axial shear (|τ| = √(τ_ψ² + τ_R²) ≥ |τ_ψ| at a FIXED σ_n), but the same force
also moves σ_n through the gyroid's Poisson strain, with a sign that alternates with the sway (`105`'s S2 force follows
the stem's strain), so in the push half it can add contact pressure — not computed (the 2026-10-22 review, finding 4).
  Consumers (the leg's two ends, in-silico §When Modifying #48), read from `106`'s consumer blocks (#4): the binding
claim's thresholds and its Scots pine price from `106`'s `consumer_ceiling_binding_claim`, its cell — the union's lowest
θ = 0 share — held to that block's named reading; the junction on the highest share — the union's θ = 0 highest per
alloy and its C44 → 0 supremum, with the founder-ratified companion over the PUBLISHED sets only beside it
(`consumer_ceiling_junction`, ⚖️ 2026-10-22), the Scots pine group's beside them. The binding cell sits under the Voigt
phase bound — tissue in the pores — so there the envelope traction is a DEMAND with no direction, and the consumer
prints the demand, never an opening (the 2026-10-22 review, finding 1).

CAN: per cell of each group (alloy · wood set · symmetrisation reading · pore reading) at θ = 0 — σᴵ per unit strain, its
Mohr circle, the strain at which each half opens on each named p₀ reading, the growth pressure each half NEEDS to stay
closed at the source day's strains (the fields named `p0_to_stay_closed*` — a need, never a sufficiency), and at the source day's two ends the open share and the friction needed where
closed; over `106`'s grid (install angle × Zener ratio, C44 → 0 included) the principal stresses' extremes, the Zener
ratio above which the tension half's averaged traction reaches p₀ on every install angle, and the compression half's friction; summaries per
group (Scots pine ⊥ green ⊥ union), over all cells and over the bare-lattice cells alone; what excluding Bruder's 2.5 MPa
costs the «every cell» headline; the verdict's smallest margin against the homogenisation error; both consumers' cells;
the mean axial shear of the anode's bond force; a fingerprint of every `106`, `105` and CEM field read, which the cache
test recomputes from the CURRENT inputs.
CANNOT: (1) say what the contact DOES once it opens or slips, or what an interlock carries — the unbonded and the
interlocked ends are the leg's step (2): a slipping interface keeps no uniform field inside a circular inclusion in an
anisotropic matrix (Wang 2009), so it lies outside this uniform-strain solution, and what partial slip, opening or
interlock do to t_L is not computed (a fully open SMOOTH envelope decouples like `106`'s soft ring; what an interlock does in tension is not computed); (2) resolve the traction on the ligament ends or inside the pores (⚠️ above), or bound its
O(cell/radius) error; (3) give the Ø15 interface — the callus against the old wood of the drilled wall: `106` reads the
ring as the host's xylem, so that wall is no interface in the model, and its traction (the matrix's exterior field at
r/a = 15/11) is not uniform and not computed; (4) give p₀ for a conifer's stem callus, its distribution around the gyroid
or its relaxation; (5) the finite length — at the ends a finite gyroid carries its axial mismatch by axial shear (the
infinite model's σᴵ_RR is its scale), and the anode's bond-force distribution; (6) everything `106` cannot (C44, the
tissue's stiffness, the bark, S5); (7) the change of σ_n the anode's axial force makes through the gyroid's Poisson
strain (Axial, above).

Run:  conda activate silken_md
      python tools/in_silico/scripts/108_gyroid_interface_contact_map.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import itertools
import json
import math
import re
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Where the perfectly bonded interface between a titanium gyroid lattice and the wood of a living stem "
                  "could stand instead as a contact pressed by a growth pressure and held by friction: on the bonded "
                  "orthotropic Eshelby solution the interface traction is exact, so it is split into its normal and "
                  "shear parts, and the friction it needs, the sectors where it opens and the growth pressure needed "
                  "to keep it closed (a lower bound on a smooth envelope, a demand elsewhere) are computed over every modelled cell of both wood groups, dry Scots pine and "
                  "green Pinaceae, against two named readings of root growth pressure at the stem strain of one "
                  "measured sway day; the direction of the homogenised verdict holds only for a smooth contact on the "
                  "lattice's envelope; the projection is checked against the closed-form solution for an isotropic "
                  "circular inclusion, no finite elements")

MECH = CACHE_DIR / "mechanical"
SRC106 = MECH / "gyroid_wood_strain_share.json"
SRC105 = MECH / "printed_part_sway_stress.json"
CEM_ANODE = REPO_ROOT / "tools/cad/cem/anchor_zone1.pine.json"
OUT = MECH / "gyroid_interface_contact_map.json"

# ── p₀: named readings of ROOT growth pressure, one primary, read 2026-10-22 (born-digital PDF; the quotes grep-verified
#    in its text layer and the pages read as images — in-silico §Critical Rules #38/#40) ─────────────────────────────────
BRUDER = ("Bruder G. R. 1998, Finite-Elemente-Simulationen und Festigkeitsanalysen von Wurzelverankerungen, Dissertation "
          "Universität Karlsruhe (TH), Wissenschaftliche Berichte FZKA 6206, Forschungszentrum Karlsruhe; doi "
          "10.5445/IR/67698 (DataCite record read 2026-10-22: creator, title, 1998, doctoral thesis)")
P0_READINGS = {                      # ascending p₀; the leg's main reading is the clamps, the turgor the secondary one
    "turgor_free_root_cells": {
        "MPa": 0.5, "page": 15, "quote": "bei etwa 0,5 MPa",
        "is": "the turgor of free-lying root cells, cited by Bruder from his ref [27] (secondary; p. 100 repeats it as "
              "«als typischer Wert 0,5 MPa») — a cell's internal pressure, not a pressure measured on a body"},
    "spring_clamps_on_poplar_roots": {
        "MPa": 0.72, "page": 100, "quote": "bis zu 0,72 MPa bei etwa 2 mm Dickenzuwachs",
        "is": "Bruder's own first field test («in einem ersten Feldversuch»): 15 spring clamps (5, 10 and 20 N/mm) on thin "
              "poplar roots (< 10 mm), read after about 2 years at about 2 mm of thickness growth («Dickenzuwachs» — a "
              "diameter for a root) — the largest over the "
              "clamps («bis zu»); compliance-limited, not a stall pressure against a rigid body, and whether it rises "
              "further Bruder left open; a broadleaf's root, not a conifer's stem callus"},
}
P0_EXCLUDED = {
    "MPa": 2.5, "pages": [15, 100], "quotes": ["bis 2,5 MPa und darüber", "2,5 MPa angegeben [86]"],
    "why": "ambiguous in Bruder, so not taken (00_07 HW.23 step (1): «2.5 МПа» не брати): p. 15 gives it for roots "
           "impeded in their expansion, measured indirectly, from his ref [28], open-ended above («und darüber»); p. 100 "
           "gives it as the soil strength at which root growth stops, from his ref [86], cross-referenced to the p. 15 "
           "section — two senses, one an indirect lower end, the other a stopping strength"}
P0_FURTHER_ON_THE_PAGES = {
    "is": "root figures on the same pages that the leg does not take (secondary in Bruder): set against the p₀ each "
          "statement needs, never used as a reading",
    "primary_growth_near_root_tip_ref85_MPa": {"axial_mean": 0.86, "axial_range": [0.24, 1.45],
                                               "radial_mean": 0.69, "radial_range": [0.51, 0.90], "page": 100},
    "bottle_neck_root_ref87_MPa": {"range": [0.4, 0.5], "page": 101},
}
P0_NAMES = tuple(P0_READINGS)
HALVES = (("tension", 1.0), ("compression", -1.0))      # the sign of the stem's bending stress at the anchor
PLACEMENTS = ("dbh_min_sensor_on_bark", "large_stem_limit")   # `105`'s depth fractions: its junction ⊥ `106`'s cell
STEM = ("median", "upper_whisker")
LOW_END, HIGH_END = "median|dbh_min_sensor_on_bark", "upper_whisker|large_stem_limit"
# `106`'s groups (its `inputs.groups`) → the cell block and the wood-reading block this script maps; `union` is both
GROUPS_READ = {"scots_pine": ("cells", "wood_readings"), "green": ("green_cells", "green_wood_readings")}
UNION = "union"
GROUP_ORDER = ("scots_pine", "green", UNION)
# every `106` and `105` field this script reads — fingerprinted, so the cache test reds on a stale `108` cache
CONSUMED_106 = ("inputs.lattice_reading", "inputs.solid_fraction_105", "inputs.theta_deg", "inputs.zener_grid",
                "inputs.groups", "wood_readings", "green_wood_readings", "cells", "green_cells",
                "theta0_share_over_modelled_set", "green_theta0_share", "union_theta0_share",
                "gyroid_binds_above_surface_strain_ue_theta0_lowest_share",
                "union_gyroid_binds_above_surface_strain_ue_theta0_lowest_share", "junction_share_sup_at_C44_zero",
                "green_junction_share_sup_at_C44_zero", "union_junction_share_sup_at_C44_zero",
                "consumer_ceiling_binding_claim", "consumer_ceiling_junction")
CONSUMED_105 = ("inputs.stem_readings_87", "inputs.depth_fraction", "inputs.solid_fraction", "zone1_members")
# the pine anode's CEM fields read — the ψ resolution and the axial envelope (the 2026-10-22 review: a CEM edit left the
# cache test green)
CONSUMED_CEM = ("outer_diameter_mm", "gyroid_period_rim_mm", "gyroid_period_mm", "length_mm")
FE_READINGS = ("axial_reading", "radial_reading")       # `105`'s two FE readings, as `106`'s threshold blocks key them
BARE = "pores_carry_nothing"                            # the one pore reading a smooth envelope is consistent with
PSI_ID = 720                # ψ points of the Mohr-identity control on [0, 2π)
PSI_BRUTE = 40000           # ψ points of the brute-force μ_max control on [0, π)
BISECT = 55                 # Zener-ratio bisection steps inside a bracket of adjacent grid points (ratio ≈ 1.19): ≪ 1e-12
CAP_106 = 1e-12             # the reproduction tolerance on `106`'s cached shares — same code, so round-off only
VOIGT_ORDER = ("LL", "TT", "RR", "TR", "LR", "LT")   # `106`'s VOIGT: (0,0) (1,1) (2,2) (1,2) (0,2) (0,1)


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def up(x: float, digits: int = 0) -> float:
    """Rounded UP — an «opens above X» / «only below X» sentence (in-silico §When Modifying #43)."""
    f = 10.0 ** digits
    return math.ceil(round(x * f, 9)) / f


def down(x: float, digits: int = 0) -> float:
    """Rounded DOWN — a «needs at least X» sentence on a lower bound (in-silico §When Modifying #43)."""
    f = 10.0 ** digits
    return math.floor(round(x * f, 9)) / f


def fingerprint(d: dict, paths: tuple[str, ...]) -> str:
    """sha256 of the canonical JSON of the fields at the dotted `paths` — what this script read of an upstream cache.
    The cache test recomputes it from the CURRENT upstream cache: a re-run upstream that moved any field read here, and
    left this cache as it was, reds there (the CI blind spot the 2026-10-22 review found)."""
    def get(path: str):
        node = d
        for part in path.split("."):
            node = node[part]
        return node
    blob = json.dumps({p: get(p) for p in paths}, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def dump_compact(obj) -> str:
    """indent-2 JSON with every list of scalars on one line — the cell lists are aligned with `p0_list_order`, and one
    value per line made the record four times longer than its content. A list holding a bracket or a brace (a string
    with one, or a nested container) is left as json.dumps writes it."""
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    return re.sub(r"\[\n\s*([^\[\]{}]*?)\n\s*\]", lambda m: "[" + re.sub(r",\n\s*", ", ", m.group(1)) + "]", text)


def mohr(sig: np.ndarray) -> tuple[float, float, float]:
    """The in-plane (L–T) Mohr circle of a stress in `106`'s Voigt order: centre c, radius r, and ψ₁ (deg) of σ₁ = c + r."""
    c, b = 0.5 * (sig[0] + sig[1]), 0.5 * (sig[0] - sig[1])
    return float(c), float(math.hypot(b, sig[5])), float(0.5 * math.degrees(math.atan2(sig[5], b)))


def traction(sig: np.ndarray, psi: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """σ_n (tension positive), τ_ψ and τ_R on the circular interface at the angles ψ — the plain projection t = σᴵ·n."""
    co, si = np.cos(psi), np.sin(psi)
    s_n = sig[0] * co * co + sig[1] * si * si + 2.0 * sig[5] * si * co
    t_psi = (sig[1] - sig[0]) * si * co + sig[5] * (co * co - si * si)
    t_r = sig[4] * co + sig[3] * si
    return s_n, t_psi, t_r


def mu_at_onset_fraction(c: float, r: float, s: float, lam: float) -> float | None:
    """μ_max at the strain λ·ε_open of the half s, which needs no p₀: with t₁ = s·c + r (the half's tensile principal) and
    ρ = r/t₁, μ_max = λ·ρ/√((1 − λ)(1 − λ + 2λρ)). None if the half never opens (t₁ ≤ 0)."""
    t1 = s * c + r
    if t1 <= 0.0:
        return None
    rho = r / t1
    return lam * rho / math.sqrt((1.0 - lam) * (1.0 - lam + 2.0 * lam * rho))


def half_map(c: float, r: float, eps: float, p0: float, s: float) -> dict:
    """One half of the sway at the remote strain ε (s = +1 tension, −1 compression), Mohr circle (c, r) per unit strain.
    opens: the averaged traction reaches p₀ somewhere (max s·σ_n ≥ p₀); open_share: arccos(κ)/π of the circumference;
    mu_req_max: the tangent from the origin to the shifted circle, ε·r/√(P² − (ε·r)²), P = p₀ − s·ε·c — None if open.
    Both rise with ε: μ² = ε²r²/((p₀ − ε·t₁)(p₀ + ε·t₂)) with t₁ = s·c + r > 0 the half's tensile principal and
    t₂ = r − s·c, so d ln μ²/dε = 2/ε + t₁/(p₀ − ε·t₁) − t₂/(p₀ + ε·t₂) > 2/ε − 1/ε > 0; κ falls with ε."""
    p, q = p0 - s * eps * c, eps * r
    t1 = s * c + r
    if r == 0.0:
        share = 1.0 if s * eps * c >= p0 else 0.0
    else:
        share = math.acos(max(-1.0, min(1.0, (p0 / eps - s * c) / r))) / math.pi
    opens = eps * t1 >= p0
    return {"opens": bool(opens), "open_share": share,
            "mu_req_max": None if opens else (q / math.sqrt(p * p - q * q) if q > 0.0 else 0.0)}


# ── Controls — each against an INDEPENDENT closed form or a brute force (in-silico §When Modifying #8) ─────────────────
def control_isotropic_traction(s106) -> float:
    """A finite isotropic inclusion in an isotropic matrix under a plane-strain remote stress with SHEAR (σ11, σ22, σ12):
    the interface traction from `106`'s Eshelby machinery and this script's projection against Goodier/Muskhelishvili's
    closed form — the inclusion's in-plane stress is P_I = f_p·P plus the deviator f_d·(D1, D2), so
    σ_n = P_I + D1·cos 2ψ + D2·sin 2ψ and τ_ψ = −D1·sin 2ψ + D2·cos 2ψ (f_p, f_d as in `106`'s control).
    CAN catch: a projection error (a factor 2 on σ_LT, a sign of τ_ψ, the Mandel √2 left on the shear), the tension-
    positive convention, the inclusion stress built from the wrong strain or tensor. CANNOT catch: anisotropy, which the
    reproduction of `106`'s shares and `106`'s own controls (Lekhnitskii's hole, the covariance) carry."""
    em, nm, ei, ni = 1.0, 0.30, 7.0, 0.20
    cm4, ci4 = s106.iso_c(em, nm), s106.iso_c(ei, ni)
    sig = np.zeros((3, 3))
    sig[0, 0], sig[1, 1], sig[0, 1], sig[1, 0] = 1.0, 0.3, 0.2, 0.2
    sig[2, 2] = nm * (sig[0, 0] + sig[1, 1])
    cm, ci = s106.mandel(cm4), s106.mandel(ci4)
    eps_inf = np.linalg.solve(cm, s106.strain_vec(sig))
    s_i = ci @ s106.inclusion_strain(cm, ci, s106.mandel(s106.eshelby_cylinder(cm4)), eps_inf) / s106.MW
    mu_m, mu_i, k_m, k_i = em / (2 * (1 + nm)), ei / (2 * (1 + ni)), 3 - 4 * nm, 3 - 4 * ni
    f_p = mu_i * (k_m + 1) / (2 * mu_i + mu_m * (k_i - 1))
    f_d = mu_i * (k_m + 1) / (mu_m + k_m * mu_i)
    p_i, d1, d2 = f_p * (sig[0, 0] + sig[1, 1]) / 2, f_d * (sig[0, 0] - sig[1, 1]) / 2, f_d * sig[0, 1]
    psi = np.linspace(0.0, 2 * math.pi, 361)
    s_n, t_psi, t_r = traction(s_i, psi)
    return float(max(np.abs(s_n - (p_i + d1 * np.cos(2 * psi) + d2 * np.sin(2 * psi))).max(),
                     np.abs(t_psi - (-d1 * np.sin(2 * psi) + d2 * np.cos(2 * psi))).max(), np.abs(t_r).max()))


def control_mu_brute(c: float, r: float, eps: float, p0: float, s: float, mu: float) -> float:
    """μ_max of `half_map` against a brute force over the circle: the value AT the tangent point (cos φ* = s·q/p, i.e.
    ψ = ψ₁ + φ*/2) and a dense ψ grid, refined around its own maximum, that must never exceed it and must reach it.
    CAN catch: a wrong tangent formula (a dropped root, P without the circle's centre, the half's sign), and a maximum
    that is not one. CANNOT catch: an error in σᴵ itself — the reproduction of `106` and the isotropic control do."""
    def mu_at(psi: np.ndarray) -> np.ndarray:
        return eps * r * np.abs(np.sin(2 * psi)) / (p0 - s * eps * (c + r * np.cos(2 * psi)))

    psi = np.linspace(0.0, math.pi, PSI_BRUTE, endpoint=False)
    coarse = mu_at(psi)
    h = math.pi / PSI_BRUTE
    k = int(np.argmax(coarse))
    grid_max = float(max(coarse.max(), mu_at(np.linspace(psi[k] - h, psi[k] + h, 20001)).max()))
    if mu == 0.0:
        assert grid_max == 0.0, "a circle of zero radius carries shear"
        return 0.0
    p, q = p0 - s * eps * c, eps * r
    phi = math.acos(s * q / p)
    at = eps * r * abs(math.sin(phi)) / (p0 - s * eps * (c + r * math.cos(phi)))
    assert grid_max <= mu * (1 + 1e-12), f"the grid exceeds the tangent maximum ({grid_max} > {mu})"
    return max(abs(at / mu - 1.0), abs(grid_max / mu - 1.0))


def control_groups_read(d106: dict) -> list[str]:
    """`106`'s groups and cell/wood blocks against what this script reads.
    CAN catch: a `106` group, cell block or wood-reading block this script does not map (the (Б) merge would have let the
    draft skip `green_cells` with every other assert green). CANNOT catch: a group whose cells sit under a key that ends
    neither in «cells» nor in «wood_readings»."""
    missing = sorted(set(d106["inputs"]["groups"]) - {*GROUPS_READ, UNION})
    blocks = {k for k in d106 if k == "cells" or k.endswith("_cells")} | {k for k in d106 if k.endswith("wood_readings")}
    read = {b for pair in GROUPS_READ.values() for b in pair}
    return missing + sorted(blocks - read)


def main() -> int:
    banner("108 — 106's bonded gyroid interface read as a pressed frictional contact: the validity map")
    s106 = _load("s106_108", "106_gyroid_wood_strain_share.py")
    d106 = json.loads(SRC106.read_text(encoding="utf-8"))
    d105 = json.loads(SRC105.read_text(encoding="utf-8"))
    cem = json.loads(CEM_ANODE.read_text(encoding="utf-8"))
    unread = control_groups_read(d106)
    assert not unread, f"106 carries groups or blocks 108 does not read: {unread} — extend 108"

    # ── 106's tensor, read from its cache (exact doubles) and held to its own cells below ────────────────────────────
    lat = d106["inputs"]["lattice_reading"]
    c11, c12, a_voigt = lat["C11_over_E_s"], lat["C12_over_E_s"], lat["zener_voigt_ceiling"]
    q_lat = c11 - c12
    phi = d106["inputs"]["solid_fraction_105"]
    assert phi == d105["inputs"]["solid_fraction"], "106's solid fraction is not 105's — re-run 106"
    theta = tuple(d106["inputs"]["theta_deg"])
    assert theta == tuple(s106.THETA_DEG), "106's cached θ grid is not its code's — re-run 106"
    a_list = [0.0, *d106["inputs"]["zener_grid"]]                  # C44 → 0 first (106's junction limit), then its grid
    assert abs(a_list[-1] / a_voigt - 1.0) < 1e-15 and all(x < y for x, y in itertools.pairwise(a_list)), \
        "106's Zener grid does not end at its ceiling or is not increasing"
    parts = {th: s106.cubic_parts(c11, c12, math.radians(th)) for th in theta}

    # the wood sets of each group, from 106's own transcriptions: WOOD (Scots pine) ⊥ green_sets() (other Pinaceae)
    sets_of = {"scots_pine": s106.WOOD, "green": {n: gs["w"] for n, gs in s106.green_sets().items()}}
    wood, group_of = {}, {}
    for grp, (cell_block, wood_block) in GROUPS_READ.items():
        for wk, wv in d106[wood_block].items():
            g, rd = wk.rsplit("|", 1)
            s66 = s106.wood_compliance(sets_of[grp][g], rd)
            assert (float(np.linalg.eigvalsh(s66).min()) > 0.0) == wv["positive_definite"], f"PD flag moved: {wk}"
            if not wv["positive_definite"]:
                continue
            cm4 = s106.to4(np.linalg.inv(s66))
            sig = np.zeros((3, 3))
            sig[0, 0] = 1.0
            cm = s106.mandel(cm4)
            assert wk not in wood, f"a wood key in two groups: {wk}"
            wood[wk] = {"cm": cm, "s": s106.mandel(s106.eshelby_cylinder(cm4)),
                        "eps": np.linalg.solve(cm, s106.strain_vec(sig)), "E_L": sets_of[grp][g]["E_L"]}
            # CAN catch: a wood tensor whose remote strain is not σ_L/E_L (a units or symmetrisation slip). CANNOT catch:
            # a wrong E_L shared by both sides (the transcription is 106's, held there to its source's aggregates)
            assert abs(wood[wk]["eps"][0] * wood[wk]["E_L"] - 1.0) < 1e-12, "ε^∞_LL is not σ_L/E_L"
        for key in d106[cell_block]:
            group_of[key] = grp
    ti_phase = {al: s106.mandel(s106.iso_c(p["E_GPa"] * 1e3, p["nu"])) for al, p in ALLOY_PROPERTIES.items()}

    def c_incl(wk: str, al: str, fill: str, th: float, a: float) -> np.ndarray:
        """`106`'s c_incl (a closure in its main()), line for line — held to its cached shares below."""
        e_s = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3
        if fill == "pores_voigt_phase_bound":
            return phi * ti_phase[al] + (1 - phi) * wood[wk]["cm"]
        base, shear = parts[th] if th in parts else s106.cubic_parts(c11, c12, math.radians(th))
        ci = e_s * (base + a * q_lat / 2 * shear)
        return ci + (1 - phi) * wood[wk]["cm"] if fill == "pores_additive_host_sapwood" else ci

    def state(wk: str, al: str, fill: str, th: float, a: float) -> tuple[float, np.ndarray]:
        """(t_L, σᴵ per unit remote strain along L in MPa, tensor components in `106`'s Voigt order)."""
        w = wood[wk]
        ci = c_incl(wk, al, fill, th, a)
        e_i = s106.inclusion_strain(w["cm"], ci, w["s"], w["eps"])
        return float(e_i[0] / w["eps"][0]), ci @ e_i / s106.MW / w["eps"][0]

    # ── Every state of 106's grid, every group: shares (held to 106's cache) and σᴵ ────────────────────────────────────
    cells = list(group_of)
    tl, sg = {}, {}
    for key in cells:
        al, g, rd, fill = key.split("|")
        wk = f"{g}|{rd}"
        if fill == "pores_voigt_phase_bound":            # θ- and C44-free: one state, broadcast over the grid
            t0, s0 = state(wk, al, fill, 0.0, a_voigt)
            tl[key] = np.full((len(theta), len(a_list)), t0)
            sg[key] = np.broadcast_to(s0, (len(theta), len(a_list), 6)).copy()
            continue
        tl[key] = np.zeros((len(theta), len(a_list)))
        sg[key] = np.zeros((len(theta), len(a_list), 6))
        for i, th in enumerate(theta):
            for j, a in enumerate(a_list):
                tl[key][i, j], sg[key][i, j] = state(wk, al, fill, th, a)

    # CAN catch: a composition copy that drifted from 106's (a 1e-9 change of one term reds), a stale 106 cache against
    # its code, a cell 106 caches and this script skipped. CANNOT catch: a 106 change made AFTER this run — the cache
    # test's fingerprint of the 106 fields read does.
    repro = 0.0
    for cell_block, _ in GROUPS_READ.values():
        for key, c in d106[cell_block].items():
            t_av, t_zero = tl[key][:, -1], tl[key][:, 0]
            mine = {"t_L_theta0_any_C44": t_av[0], "t_L_at_voigt_C44_min_over_theta": t_av.min(),
                    "t_L_at_voigt_C44_max_over_theta": t_av.max(), "t_L_at_C44_zero_max_over_theta": t_zero.max()}
            for fld, v in mine.items():
                repro = max(repro, abs(v / c[fld] - 1.0))
            assert theta[int(np.argmin(t_av))] == c["theta_of_min_deg"], f"106's argmin angle not reproduced: {key}"
            assert theta[int(np.argmax(t_zero))] == c["theta_of_max_at_C44_zero_deg"], f"106's C44=0 angle: {key}"
    assert repro <= CAP_106, f"106's cached shares not reproduced (worst relative {repro}) — re-run 106 or fix c_incl"

    # ── Controls on every state ───────────────────────────────────────────────────────────────────────────────────────
    ctl_iso = control_isotropic_traction(s106)
    assert ctl_iso < 1e-12, f"isotropic closed-form traction control failed: {ctl_iso}"
    psi_id = np.linspace(0.0, 2 * math.pi, PSI_ID, endpoint=False)
    axial_worst, mohr_worst, c44_free_worst, s1_drop_worst = 0.0, 0.0, 0.0, 0.0
    circles = {}
    for key in cells:
        arr = sg[key]
        scale = float(np.abs(arr).max())
        axial_worst = max(axial_worst, float(np.hypot(arr[..., 3], arr[..., 4]).max()) / scale)
        c_ = 0.5 * (arr[..., 0] + arr[..., 1])
        b_ = 0.5 * (arr[..., 0] - arr[..., 1])
        r_ = np.hypot(b_, arr[..., 5])
        psi1 = 0.5 * np.arctan2(arr[..., 5], b_)
        circles[key] = (c_, r_, psi1)
        for i in range(len(theta)):
            for j in (0, len(a_list) // 2, len(a_list) - 1):
                s_n, t_psi, _ = traction(arr[i, j], psi_id)
                d = 2.0 * (psi_id - psi1[i, j])
                mohr_worst = max(mohr_worst, float(max(np.abs(s_n - (c_[i, j] + r_[i, j] * np.cos(d))).max(),
                                                       np.abs(t_psi + r_[i, j] * np.sin(d)).max())) / scale)
        c44_free_worst = max(c44_free_worst, float(np.abs(arr[0] - arr[0, -1]).max()) / scale)
        s1_drop_worst = max(s1_drop_worst, float((-(np.diff(c_ + r_, axis=1))).max()) / scale)
    # τ_R ≡ 0 — CAN catch: a load or a lattice rotation that breaks the R → −R mirror (an axis mix-up). CANNOT catch: a
    # finite length or a bending gradient along R, which the model has not.
    assert axial_worst < 1e-12, f"τ_R is not zero ({axial_worst}) — the R → −R mirror is broken"
    # Mohr identity — a CONSISTENCY check of two parametrisations of the same σᴵ (the projection ⊥ c, r, ψ₁), not an
    # independent one: CAN catch a slip in either form. CANNOT catch an error in σᴵ (the reproduction and the isotropic
    # closed form do).
    assert mohr_worst < 1e-12, f"the projection is not the Mohr circle ({mohr_worst})"
    # θ = 0 free of C44 — CAN catch: a C44 term leaking onto the cube axis (a rotation error). CANNOT catch: a wrong C44
    # off the axis.
    assert c44_free_worst < 1e-9, f"σᴵ at θ = 0 moves with C44 ({c44_free_worst})"
    # σ₁ never falls as C44 rises — the premise of the Zener-threshold bisection. CAN catch: a non-monotone grid row
    # (then the threshold form is void). CANNOT catch: a fall between grid points (the bisection runs only inside a
    # bracket the grid shows).
    assert s1_drop_worst < 1e-12, f"σ₁ falls as C44 rises somewhere ({s1_drop_worst}) — the Zener threshold form is void"

    # ── The scale: the source day's strain at the gyroid (87 → 105) ────────────────────────────────────────────────────
    stem = d105["inputs"]["stem_readings_87"]
    frac = d105["inputs"]["depth_fraction"]
    strains = {f"{rd}|{pl}": stem[rd]["surface_strain_ue"] * frac[pl] for rd in STEM for pl in PLACEMENTS}
    assert min(strains, key=strains.get) == LOW_END and max(strains, key=strains.get) == HIGH_END, "the ends moved"
    p0v = {n: P0_READINGS[n]["MPa"] for n in P0_NAMES}
    p0_hi = max(p0v.values())

    # ── ψ-resolution of the homogenised traction: one lattice cell on the envelope (the CEM's period, rim ⊥ core) ──────
    radius = cem["outer_diameter_mm"] / 2
    periods = [cem["gyroid_period_rim_mm"], cem["gyroid_period_mm"]]
    psi_resolution = {"envelope_radius_mm": radius, "period_rim_core_mm": periods,
                      "cells_across_diameter": [2 * radius / p for p in reversed(periods)],
                      "psi_span_of_one_cell_deg": [math.degrees(p / radius) for p in periods],
                      "is": "a one-cell patch of the envelope spans this arc of ψ; the homogenised traction equals the "
                            "patch average only to leading order in cell/radius, so the ψ-resolved open shares and μ "
                            "maxima carry an unquantified O(cell/radius) error"}

    # ── θ = 0: the C44-free map, every cell ────────────────────────────────────────────────────────────────────────────
    out_cells, brute_worst, lam_worst = {}, 0.0, 0.0
    for key in cells:
        sig0 = sg[key][0, -1]
        c0, r0, psi10 = mohr(sig0)
        assert abs(psi10) < 1e-9 and abs((c0 + r0) / sig0[0] - 1.0) < 1e-12, f"θ = 0 σ₁ not along L: {key}"
        t1 = {h: s * c0 + r0 for h, s in HALVES}
        half_on = {h: mu_at_onset_fraction(c0, r0, s, 0.5) for h, s in HALVES}
        for h, s in HALVES:                  # the p₀-free form against half_map at half each reading's onset
            for n in P0_NAMES:
                if t1[h] > 0:
                    m = half_map(c0, r0, 0.5 * p0v[n] / t1[h], p0v[n], s)["mu_req_max"]
                    lam_worst = max(lam_worst, abs(m / half_on[h] - 1.0))
        block = {"sigma_I_MPa_per_unit_strain": {n: float(sig0[k]) for k, n in enumerate(VOIGT_ORDER)
                                                 if n in ("LL", "TT", "RR", "LT")},     # TR = LR = 0 (asserted)
                 "t_L": float(tl[key][0, -1]),
                 "sigma1": c0 + r0, "sigma2": c0 - r0,       # in-plane principal, MPa per unit strain; ψ₁ = 0 (asserted)
                 "opening_onset_ue": {h: [p0v[n] / t1[h] * 1e6 if t1[h] > 0 else None for n in P0_NAMES]
                                      for h, _ in HALVES},
                 "mu_req_max_at_half_onset": half_on,
                 "at_source_day": {h: {"open_share": {}, "mu_req_max": {}} for h, _ in HALVES}}
        for end, ek in (("low", LOW_END), ("high", HIGH_END)):
            for h, s in HALVES:
                rows = [half_map(c0, r0, strains[ek] * 1e-6, p0v[n], s) for n in P0_NAMES]
                block["at_source_day"][h]["open_share"][end] = [x["open_share"] for x in rows]
                block["at_source_day"][h]["mu_req_max"][end] = [x["mu_req_max"] for x in rows]
                for n, x in zip(P0_NAMES, rows, strict=True):
                    if x["mu_req_max"] is not None:
                        brute_worst = max(brute_worst, control_mu_brute(c0, r0, strains[ek] * 1e-6, p0v[n], s,
                                                                        x["mu_req_max"]))
        out_cells[key] = {"theta0": block}
    assert brute_worst < 1e-6, f"the tangent μ_max disagrees with the brute force ({brute_worst})"
    # the p₀-free λ-form against half_map — two closed forms of one tangent: CAN catch an algebra slip in either. CANNOT
    # catch a wrong σᴵ.
    assert lam_worst < 1e-12, f"the p₀-free form of μ_max disagrees with half_map ({lam_worst})"

    # ── Off the axis: 106's grid (lattice cells) ─────────────────────────────────────────────────────────────────────
    def a_star(key: str, i: int, target: float) -> float | None:
        """The Zener ratio below which σ₁(θ_i, A) < target (σ₁ non-decreasing in A — asserted); None if not even at 0."""
        c_, r_, _ = circles[key]
        s1 = c_[i] + r_[i]
        if s1[0] >= target:
            return None
        if s1[-1] < target:
            return a_list[-1]
        j = int(np.searchsorted(s1, target))                     # s1[j-1] < target ≤ s1[j]
        lo, hi = a_list[j - 1], a_list[j]
        al, g, rd, fill = key.split("|")
        for _ in range(BISECT):
            mid = 0.5 * (lo + hi)
            c, r, _ = mohr(state(f"{g}|{rd}", al, fill, theta[i], mid)[1])
            lo, hi = (mid, hi) if c + r < target else (lo, mid)
        return 0.5 * (lo + hi)

    comp_states = {}
    for key in cells:
        if key.endswith("pores_voigt_phase_bound"):
            continue
        c_, r_, _ = circles[key]
        s1, s2 = c_ + r_, c_ - r_
        i1, j1 = np.unravel_index(int(np.argmin(s1)), s1.shape)
        i2, j2 = np.unravel_index(int(np.argmax(s2)), s2.shape)
        grid = {"sigma1": [float(s1.min()), float(s1.max())], "sigma1_min_at": [theta[i1], a_list[j1]],
                "sigma2": [float(s2.min()), float(s2.max())], "sigma2_max_at": [theta[i2], a_list[j2]],
                "sigma1_min_over_theta_at_voigt_ceiling": float(s1[:, -1].min()),
                "theta_of_that_min_deg": theta[int(np.argmin(s1[:, -1]))],
                "zener_above_which_tension_half_opens_on_every_angle": {}}
        comp_states[key] = {}
        for end, ek in (("low", LOW_END), ("high", HIGH_END)):
            e = strains[ek] * 1e-6
            stars_n = []
            comp_states[key][end] = []
            for n in P0_NAMES:
                stars = [x for i in range(len(theta)) if (x := a_star(key, i, p0v[n] / e)) is not None]
                stars_n.append(max(stars) if stars else None)
                p, q = p0v[n] + e * c_, e * r_                    # the compression half (s = −1) over the grid
                closed = p > q
                mus = q[closed] / np.sqrt(p[closed] ** 2 - q[closed] ** 2) if closed.any() else np.array([])
                comp_states[key][end].append({"open": int((~closed).sum()), "states": int(closed.size),
                                              "mu": [float(mus.min()), float(mus.max())] if mus.size else None})
            grid["zener_above_which_tension_half_opens_on_every_angle"][end] = stars_n
        out_cells[key]["grid"] = grid

    # ── Summaries per group: Scots pine ⊥ green ⊥ union ─────────────────────────────────────────────────────────────
    def rng(vals):
        vals = list(vals)
        return [min(vals), max(vals)]

    def summarise(keys: list[str]) -> dict:
        """Every list aligned with P0_NAMES (the cache's `p0_list_order`); "low"/"high" = the source day's two ends."""
        th0 = {k: out_cells[k]["theta0"] for k in keys}
        bare = [k for k in keys if k.endswith("|pores_carry_nothing")]
        summ = {"cells": len(keys), "bare_lattice_cells": len(bare),
                "theta0": {"opening_onset_ue": {}, "mu_req_max_at_half_onset": {}, "p0_to_stay_closed_MPa": {},
                           "at_source_day": {}},
                "grid": {"opening_onset_tension_ue": {}, "opening_onset_tension_at_voigt_ceiling_ue": {},
                         "zener_above_which_tension_half_opens_on_every_angle": {}, "compression_half": {}}}
        for h, s in HALVES:
            cols = list(zip(*(b["opening_onset_ue"][h] for b in th0.values()), strict=True))
            summ["theta0"]["opening_onset_ue"][h] = {
                n: {"range": rng(v for v in col if v is not None), "cells_never": sum(v is None for v in col)}
                for n, col in zip(P0_NAMES, cols, strict=True)}
            summ["theta0"]["mu_req_max_at_half_onset"][h] = rng(
                b["mu_req_max_at_half_onset"][h] for b in th0.values() if b["mu_req_max_at_half_onset"][h] is not None)
            summ["theta0"]["p0_to_stay_closed_MPa"][h] = {
                ek: rng(max(0.0, e * 1e-6 * (b["sigma1"] if s > 0 else -b["sigma2"])) for b in th0.values())
                for ek, e in strains.items()}
            summ["theta0"]["at_source_day"][h] = {}
            for end in ("low", "high"):
                per = {}
                for idx, n in enumerate(P0_NAMES):
                    shares = [b["at_source_day"][h]["open_share"][end][idx] for b in th0.values()]
                    mus = [b["at_source_day"][h]["mu_req_max"][end][idx] for b in th0.values()]
                    fin = [m for m in mus if m is not None]
                    per[n] = {"cells_open": sum(m is None for m in mus), "cells": len(mus),
                              "bare_lattice_cells_open": sum(th0[k]["at_source_day"][h]["mu_req_max"][end][idx] is None
                                                             for k in bare),
                              "open_share": rng(shares), "mu_req_max_closed": rng(fin) if fin else None}
                summ["theta0"]["at_source_day"][h][end] = per
        # the pole traction against the wood's own bending stress σ_L = E_L·ε — what the opening does not hang on
        summ["theta0"]["sigma1_over_E_L"] = rng(b["sigma1"] / wood[k.split("|", 1)[1].rsplit("|", 1)[0]]["E_L"]
                                                for k, b in th0.items())
        lattice = {k: out_cells[k]["grid"] for k in keys if "grid" in out_cells[k]}
        s1_top = max(g["sigma1"][1] for g in lattice.values())
        s1_bot = min(g["sigma1"][0] for g in lattice.values())
        s1_bot_v = min(g["sigma1_min_over_theta_at_voigt_ceiling"] for g in lattice.values())
        # a state whose largest in-plane principal is ≤ 0 never opens in the tension half: its onset is None, not p₀/σ₁
        summ["grid"]["lattice_cells_with_sigma1_nonpositive_somewhere"] = sum(g["sigma1"][0] <= 0.0
                                                                              for g in lattice.values())
        for n in P0_NAMES:
            summ["grid"]["opening_onset_tension_ue"][n] = [p0v[n] / s1_top * 1e6,
                                                           p0v[n] / s1_bot * 1e6 if s1_bot > 0.0 else None]
            summ["grid"]["opening_onset_tension_at_voigt_ceiling_ue"][n] = (
                p0v[n] / s1_bot_v * 1e6 if s1_bot_v > 0.0 else None)
        for end in ("low", "high"):
            summ["grid"]["zener_above_which_tension_half_opens_on_every_angle"][end] = {}
            summ["grid"]["compression_half"][end] = {}
            for idx, n in enumerate(P0_NAMES):
                stars = [g["zener_above_which_tension_half_opens_on_every_angle"][end][idx] for g in lattice.values()]
                fin = [x for x in stars if x is not None]
                summ["grid"]["zener_above_which_tension_half_opens_on_every_angle"][end][n] = {
                    "max": max(fin) if fin else None, "cells_opening_at_every_ratio": sum(x is None for x in stars)}
                cs = [comp_states[k][end][idx] for k in lattice]
                mus = [x for c in cs if c["mu"] for x in c["mu"]]
                summ["grid"]["compression_half"][end][n] = {
                    "states_open": sum(c["open"] for c in cs), "states": sum(c["states"] for c in cs),
                    "mu_req_max_closed": rng(mus) if mus else None}
        s1_at = min(lattice.items(), key=lambda kv: kv[1]["sigma1"][0])
        summ["grid"]["sigma1_min_cell"] = {"cell": s1_at[0], "theta_deg": s1_at[1]["sigma1_min_at"][0],
                                           "zener": s1_at[1]["sigma1_min_at"][1], "sigma1": s1_at[1]["sigma1"][0]}
        summ["grid"]["theta_of_lowest_sigma1_at_voigt_ceiling"] = sorted(
            {g["theta_of_that_min_deg"] for g in lattice.values()})
        return summ

    keys_of = {grp: [k for k in cells if group_of[k] == grp] for grp in GROUPS_READ}
    keys_of[UNION] = list(cells)
    summary = {grp: summarise(keys_of[grp]) for grp in GROUP_ORDER}
    # a smooth envelope is consistent only with the bare lattice: its statements (an opening, a friction lower bound)
    # are taken over these cells alone; the additive and Voigt cells give the demand (the 2026-10-22 review, finding 3)
    summary_bare = {grp: summarise([k for k in keys_of[grp] if k.endswith(f"|{BARE}")]) for grp in GROUP_ORDER}

    # ── Consumers, from 106's consumer blocks (#4): the binding claim's thresholds and price from
    #    `consumer_ceiling_binding_claim`, its cell the union's lowest θ = 0 share; the junction on the highest share,
    #    the C44 → 0 supremum and its published-sets-only companion ────────────────────────────────────────────────────
    th0_all = {k: v["theta0"] for k, v in out_cells.items()}
    gsets = s106.green_sets()

    def citation(cell_key: str) -> str:
        """`106`'s citation (a closure inside its main()), line for line — the consumer blocks name their cells by it."""
        _, name, rd, fill = cell_key.split("|")
        if name in gsets:
            src = s106.GREEN_SOURCES[gsets[name]["source"]]
            return f"{src['citation']}, doi {src['doi']}, {gsets[name]['where']}; {rd} reading, {fill}"
        return f"Güntekin & Akar 2019, doi 10.12841/wood.1644-3985.220.09, group {name}; {rd} reading, {fill}"

    cbc = d106["consumer_ceiling_binding_claim"]
    blocks_bind = {UNION: ("union_theta0_share", "union_gyroid_binds_above_surface_strain_ue_theta0_lowest_share",
                           cbc["binds_above_ue_large_stem_sf2"]),
                   "scots_pine": ("theta0_share_over_modelled_set",
                                  "gyroid_binds_above_surface_strain_ue_theta0_lowest_share",
                                  cbc["price_scots_pine_group"]["binds_above_ue_large_stem_sf2"])}
    binding = {}
    for grp, (k_share, k_thr, consumer) in blocks_bind.items():
        t0s, ba = d106[k_share], d106[k_thr]
        binding[grp] = {}
        for al in ALLOY_PROPERTIES:
            cell = t0s[al]["lowest_cell"]
            b = th0_all[cell]
            assert abs(b["t_L"] / t0s[al]["lowest"] - 1.0) < CAP_106, f"106's lowest θ = 0 share not this cell's: {al}"
            thr = {fk: consumer[fk][al] for fk in FE_READINGS}
            # the consumer block is what 108 reads; the group derivation it summarises must name the same thresholds,
            # and the block's named reading must be this cell's (the 2026-10-22 review: they were tied by nothing)
            assert thr == {fk: ba[fk][al][s106.CELL_LS] for fk in FE_READINGS}, \
                f"106's consumer block and its {grp} threshold block disagree: {al}"
            fill = cell.split("|")[3]
            if grp == UNION:          # the whole named reading — wood set, source, symmetrisation and pores
                assert cbc["reading_per_alloy"][al] == citation(cell), f"106's binding reading is not this cell: {al}"
            binding[grp][al] = {
                "cell": cell, "pore_reading": fill, "smooth_envelope_consistent": fill == BARE,
                "threshold_ue_106": thr,
                "opening_onset_tension_ue": b["opening_onset_ue"]["tension"],
                "threshold_over_onset_min": min(thr[fk] / x for fk in thr for x in b["opening_onset_ue"]["tension"]),
                "p0_to_stay_closed_at_threshold_MPa": {fk: thr[fk] * 1e-6 * b["sigma1"] for fk in thr}}
    blocks_hi = {UNION: "union_theta0_share", "scots_pine": "theta0_share_over_modelled_set",
                 "green": "green_theta0_share"}
    blocks_sup = {UNION: "union_junction_share_sup_at_C44_zero", "scots_pine": "junction_share_sup_at_C44_zero",
                  "green": "green_junction_share_sup_at_C44_zero"}
    def sup_block(key: str, th_deg: float, t_l: float, sig: np.ndarray) -> dict:
        """A C44 → 0 junction cell: its Mohr circle, where its tension half's averaged traction reaches each p₀, and
        on which readings it does so at each of the source day's strains. A supremum cell is bare lattice (asserted
        where it is built), so a smooth envelope is consistent with it."""
        c_s, r_s, _ = mohr(sig)
        s1 = c_s + r_s
        return {"cell": key, "theta_deg": th_deg, "t_L": t_l, "zener": 0.0,
                "mohr": {"centre": c_s, "radius": r_s, "sigma1": s1, "sigma2": c_s - r_s},
                "in_plane_stress_isotropic": r_s <= 1e-9 * abs(c_s),
                "opening_onset_tension_ue": [p0v[n] / s1 * 1e6 for n in P0_NAMES],
                "p0_to_stay_closed_MPa": {ek: e * 1e-6 * s1 for ek, e in strains.items()},
                "tension_half_open_at": {ek: [n for n in P0_NAMES if e * s1 * 1e-6 >= p0v[n]]
                                         for ek, e in strains.items()}}

    junction = {}
    for grp in GROUP_ORDER:
        t0s = d106[blocks_hi[grp]]
        sup_key = max(keys_of[grp], key=lambda k: tl[k][:, 0].max())
        sup_th = theta[int(np.argmax(tl[sup_key][:, 0]))]
        t_sup, s_sup = tl[sup_key][theta.index(sup_th), 0], sg[sup_key][theta.index(sup_th), 0]
        assert abs(t_sup / d106[blocks_sup[grp]] - 1.0) < CAP_106, f"106's junction supremum not reproduced: {grp}"
        assert sup_key.endswith(f"|{BARE}"), f"the junction supremum is not a bare-lattice cell: {grp}"
        junction[grp] = {
            "theta0_highest": {al: {"cell": t0s[al]["highest_cell"], "t_L": t0s[al]["highest"],
                                    "opening_onset_tension_ue": th0_all[t0s[al]["highest_cell"]]["opening_onset_ue"][
                                        "tension"]}
                               for al in ALLOY_PROPERTIES},
            "sup_C44_zero": sup_block(sup_key, sup_th, t_sup, s_sup)}
    cj = d106["consumer_ceiling_junction"]
    for al, v in junction[UNION]["theta0_highest"].items():      # the θ = 0 junction cell is the one 106's block names
        assert cj["theta0_highest_per_alloy"][al]["share"] == v["t_L"] and \
            cj["theta0_highest_per_alloy"][al]["reading"] == citation(v["cell"]), f"106's θ = 0 junction cell moved: {al}"
    sup_106 = cj["off_axis_sup_at_C44_zero"]
    assert (junction[UNION]["sup_C44_zero"]["cell"], junction[UNION]["sup_C44_zero"]["theta_deg"]) == \
        (sup_106["cell"], sup_106["theta_deg"]), "106's junction ceiling names another cell — re-run 106 or 108"
    # the founder-ratified companion (⚖️ 2026-10-22, «поруч із 9.840 … супремум поза віссю лише на опублікованих
    # наборах»): the union's supremum without Davies' raw ESM means, which are OUR assembly — read from 106's consumer
    # block and recomputed here (the 2026-10-22 review: the consumer had dropped it)
    pub = cj["off_axis_sup_at_C44_zero_published_sets_only"]
    al_p, g_p, rd_p, fill_p = pub["cell"].split("|")
    assert pub["cell"] in group_of and fill_p == BARE, f"106's published-sets supremum is not a bare cell 108 maps: {pub}"
    t_pub, s_pub = state(f"{g_p}|{rd_p}", al_p, fill_p, pub["theta_deg"], 0.0)
    assert abs(t_pub / pub["share"] - 1.0) < CAP_106, "106's published-sets junction supremum not reproduced"
    assert junction["scots_pine"]["sup_C44_zero"]["t_L"] <= t_pub, \
        "the Scots pine supremum tops the published-sets companion — it is no longer the union's"
    junction[UNION]["sup_C44_zero_published_sets_only"] = {
        **sup_block(pub["cell"], pub["theta_deg"], t_pub, s_pub), "over": pub["over"]}

    # ── Axial: the anode's bond force (105's S2 path) through the same envelope — its mean printed for scale, never
    #    paired with a 106 cell (105's bond states are not 106's cells — in-silico §When Modifying #45 ⊕); its effect on
    #    the friction needed has no direction here (the docstring's Axial) ────────────────────────────────────────────
    area = math.pi * cem["outer_diameter_mm"] * cem["length_mm"]
    z1 = d105["zone1_members"]
    axial = {"envelope_mm2": area, "envelope": f"π × {cem['outer_diameter_mm']} × {cem['length_mm']} mm (the CEM)",
             "effect_on_friction_needed": "no direction: the force adds axial shear (|τ| = √(τ_ψ² + τ_R²) ≥ |τ_ψ| at a "
                                          "FIXED σ_n), and it also moves σ_n through the gyroid's Poisson strain, with a "
                                          "sign that alternates with the sway — not computed (the 2026-10-22 review, "
                                          "finding 4)",
             "states": {}}
    for bond in ("anode_bond_stiff", "anode_bond_soft"):
        for kind in ("state3_rigid_tie_max", "rigid_sleeve"):
            for rd in STEM:
                fs = {k.split("|")[0]: v["force_N"] for k, v in z1.items() if k.endswith(f"|{bond}|{kind}|{rd}")}
                assert set(fs) == {"a_flange_on_bark", "b_zone3_fit"}, f"105's force rows moved: {bond} {kind} {rd}"
                f = max(fs.values())
                axial["states"][f"{bond}|{kind}|{rd}"] = {"force_N": f, "mean_shear_MPa": f / area}
    axial["mean_shear_MPa_range"] = rng(v["mean_shear_MPa"] for v in axial["states"].values())

    # ── What excluding Bruder's 2.5 MPa costs: the cells whose averaged tension traction at each of the source day's
    #    ends stays BELOW it — a fact about the averaged traction, no holding claim (the 2026-10-22 review) ────────────
    excl = P0_EXCLUDED["MPa"]
    excluded_price = {"MPa": excl, "is": "cells (θ = 0) whose averaged tension traction ε·σ₁ stays below the excluded "
                                         "2.5 MPa at each of the source day's two ends — what the «every cell» headline "
                                         "stands on; a fact about the averaged traction, no holding claim"}
    for grp in GROUP_ORDER:
        bare_k = [k for k in keys_of[grp] if k.endswith(f"|{BARE}")]
        excluded_price[grp] = {end: {"cells_below": sum(strains[ek] * 1e-6 * th0_all[k]["sigma1"] < excl
                                                        for k in keys_of[grp]),
                                     "cells": len(keys_of[grp]),
                                     "bare_lattice_cells_below": sum(strains[ek] * 1e-6 * th0_all[k]["sigma1"] < excl
                                                                     for k in bare_k),
                                     "bare_lattice_cells": len(bare_k)}
                               for end, ek in (("low", LOW_END), ("high", HIGH_END))}

    # ── The verdict's smallest margin against the homogenisation error. A smooth envelope opens wherever a patch average
    #    of the local traction reaches p₀. The patch average of the HOMOGENISED field over one cell's arc Δ centred on
    #    the pole is exact — σ_n = c + r·cos 2ψ averages to c + r·sin Δ/Δ — so only what homogenisation leaves out is
    #    unknown; taken relative to the pole traction ε·σ₁ as C·Δ·ε·σ₁, the «every bare cell opens» verdict holds while
    #    C < (patch − p₀)/(Δ·ε·σ₁) at the tightest bare cell, the higher reading and the day's low end — the cell picked
    #    by that constant, not by the patch margin (the 2026-10-24 review, З1). Δ on BOTH periods: the
    #    rim's (the cell actually on the envelope) and the core's (the conservative end) — the 2026-10-22 review (F6) ──
    eps_lo = strains[LOW_END] * 1e-6
    bare_union = [k for k in keys_of[UNION] if k.endswith(f"|{BARE}")]
    margin_rows = {}
    for tag, per in (("rim", cem["gyroid_period_rim_mm"]), ("core", cem["gyroid_period_mm"])):
        arc = per / radius
        sinc = math.sin(arc) / arc
        patch = {k: eps_lo * (0.5 * (th0_all[k]["sigma1"] + th0_all[k]["sigma2"])
                              + 0.5 * (th0_all[k]["sigma1"] - th0_all[k]["sigma2"]) * sinc) for k in bare_union}
        const = {k: (patch[k] - p0_hi) / (arc * eps_lo * th0_all[k]["sigma1"]) for k in bare_union}
        k_min = min(const, key=const.get)
        margin_rows[tag] = {"period_mm": per, "cell_arc_rad": arc, "curvature_factor_sin_arc_over_arc": sinc,
                            "tightest_bare_cell": k_min, "patch_need_MPa": patch[k_min],
                            "pole_need_MPa": eps_lo * th0_all[k_min]["sigma1"],
                            "margin_over_higher_p0": patch[k_min] / p0_hi,
                            "constant_below_which_every_bare_cell_still_opens": const[k_min]}
    psi_resolution["margin_vs_homogenisation_error"] = {
        "is": "the patch average of the homogenised traction over one cell's arc at the pole, exact (c + r·sin Δ/Δ), "
              "against the higher named p₀ at the day's low end; the remaining error, relative to the pole traction "
              "ε·σ₁, is C·Δ·ε·σ₁ with C unknown — the verdict holds while C < (patch − p₀)/(Δ·ε·σ₁), printed at the "
              "bare-lattice cell where that constant is smallest", **margin_rows}

    # ── The verdict, built from the numbers ──────────────────────────────────────────────────────────────────────────
    lo_n, hi_n = min(P0_NAMES, key=p0v.get), max(P0_NAMES, key=p0v.get)
    label = {"scots_pine": "the Scots pine group", "green": "the green group", UNION: "the union"}
    sb = summary_bare

    def open_clause(grp: str, summ: dict, what: str) -> str:
        """How many θ = 0 cells the tension half's averaged traction exceeds p₀ in, at the day's two ends on the named
        readings."""
        sd = summ[grp]["theta0"]["at_source_day"]["tension"]
        counts = [sd[end][n]["cells_open"] for end in ("low", "high") for n in P0_NAMES]
        m = summ[grp]["cells"]
        return f"every one of its {m} {what}" if min(counts) == m else f"at least {min(counts)} of its {m} {what}"

    need = {grp: sb[grp]["theta0"]["p0_to_stay_closed_MPa"]["tension"] for grp in GROUP_ORDER}
    need_min = {grp: need[grp][LOW_END][0] for grp in GROUP_ORDER}
    half_t = sb[UNION]["theta0"]["mu_req_max_at_half_onset"]["tension"]
    on_c = sb[UNION]["theta0"]["opening_onset_ue"]["compression"]
    comp_mu = [sb[UNION]["theta0"]["at_source_day"]["compression"][end][n]["mu_req_max_closed"]
               for end in ("low", "high") for n in P0_NAMES]
    comp_mu = [x for x in comp_mu if x is not None]
    zstar = [sb[UNION]["grid"]["zener_above_which_tension_half_opens_on_every_angle"][end][n]["max"]
             for end in ("low", "high") for n in P0_NAMES]
    zstar_fin = [z for z in zstar if z is not None]
    bind_u = binding[UNION]
    ratio_bind = min(v["threshold_over_onset_min"] for v in bind_u.values())
    al_bind = min(bind_u, key=lambda al: bind_u[al]["threshold_over_onset_min"])
    p0_bind = min(bind_u[al_bind]["p0_to_stay_closed_at_threshold_MPa"].values())   # the sentence's own alloy
    fill_bind = bind_u[al_bind]["pore_reading"]
    sup = junction[UNION]["sup_C44_zero"]
    sup_pub = junction[UNION]["sup_C44_zero_published_sets_only"]
    ep = excluded_price
    excl_clause = (f" — had it been taken, the averaged tension traction at the day's {strains[LOW_END]:.0f} µε would "
                   f"stay below it in "
                   + " and ".join(f"{ep[g]['low']['cells_below']} of {ep[g]['low']['cells']} cells ({label[g]}; "
                                  f"{ep[g]['low']['bare_lattice_cells_below']} of {ep[g]['low']['bare_lattice_cells']} "
                                  f"bare lattice)" for g in GROUPS_READ)
                   + ", a fact about the averaged traction and no holding claim —")
    further_max = max(P0_FURTHER_ON_THE_PAGES["primary_growth_near_root_tip_ref85_MPa"]["axial_range"][1],
                      P0_FURTHER_ON_THE_PAGES["primary_growth_near_root_tip_ref85_MPa"]["radial_range"][1],
                      P0_FURTHER_ON_THE_PAGES["bottle_neck_root_ref87_MPa"]["range"][1])
    if fill_bind == BARE:
        bind_clause = (f"a bare-lattice cell, so a smooth envelope opens there at least {down(ratio_bind, 1):.1f}× below "
                       f"the binding strain ({al_bind}), and only a p₀ of at least {down(p0_bind, 1):.1f} MPa could "
                       f"keep it from opening up to that strain")
    else:
        bind_clause = (f"the {fill_bind} reading, which puts tissue in the pores: the envelope is no contact surface "
                       f"there and σᴵ a bound tensor's stress) the averaged envelope traction reaches p₀ "
                       f"{down(ratio_bind, 1):.1f}× below the binding strain ({al_bind}), and only a p₀ of at least "
                       f"{down(p0_bind, 1):.1f} MPa would offset it up to that strain — a demand on the interlocked "
                       f"composite, with no direction")

    def jn_clause(s: dict) -> str:
        return (f"at the source day's upper whisker on a large stem on {len(s['tension_half_open_at'][HIGH_END])} of "
                f"{len(P0_NAMES)} named readings and at its median on a DBH-38 bark on "
                f"{len(s['tension_half_open_at'][LOW_END])}")

    verdict = (
        "Read as a SMOOTH contact on the gyroid's envelope — its local normal the envelope's, pressed by a growth pressure "
        "p₀ and held by friction, with no adhesion; consistent only with the bare-lattice cells ("
        + " ⊥ ".join(str(sb[g]["cells"]) for g in GROUPS_READ)
        + "), the cells with tissue in the pores giving the demand on an interlocked composite — the bonded field of 106 "
        f"is carried around the interface by normal traction and in-plane shear; the infinite cylinder's axial shear is "
        f"zero. With a cube axis on the stem's axis (θ = 0, free of C44) the tension half of a bare-lattice cell stays "
        f"closed at the source day's strain ({strains[LOW_END]:.0f}–{strains[HIGH_END]:.0f} µε at the gyroid) only "
        f"under p₀ of at least "
        + " ⊥ ".join(f"{down(need_min[g], 2):.2f} MPa ({label[g]})" for g in GROUPS_READ)
        + " — " + " ⊥ ".join(f"{down(need_min[g] / p0_hi, 1):.1f}×" for g in GROUPS_READ)
        + f" the higher named root reading ({p0_hi} MPa, Bruder's clamps; the turgor reading is {p0v[lo_n]} MPa); the "
        f"{P0_EXCLUDED['MPa']} MPa Bruder uses in two senses is not taken{excl_clause} and the highest further root "
        f"figure on his pages ({further_max} MPa) "
        f"{'stays below' if further_max < min(need_min.values()) else 'reaches'} the lowest p₀ needed. On both named "
        f"readings the tension half's averaged traction exceeds p₀ at both ends of the day in "
        + " and ".join(f"{open_clause(g, sb, 'bare-lattice cells')} ({label[g]})" for g in GROUPS_READ)
        + " — an opening on a smooth envelope — and, as a demand, in "
        + " and ".join(f"{open_clause(g, summary, 'cells')} ({label[g]})" for g in GROUPS_READ)
        + "; on a bare-lattice cell it opens the poles facing along the stem above "
        + " ⊥ ".join(f"{up(sb[g]['theta0']['opening_onset_ue']['tension'][lo_n]['range'][0]):.0f}–"
                      f"{up(sb[g]['theta0']['opening_onset_ue']['tension'][hi_n]['range'][1]):.0f} µε ({label[g]})"
                      for g in GROUPS_READ)
        + f", and at half that strain the friction needed is already at least {down(half_t[0], 2):.2f}–"
        f"{down(half_t[1], 2):.2f} (no p₀). In the compression half the averaged traction at the poles facing around the "
        f"stem first reaches p₀ at {down(on_c[lo_n]['range'][0]):.0f} µε on a bare-lattice cell, and where it stays "
        f"below p₀ at the source day's strain the friction a bare-lattice cell needs is at least "
        f"{down(min(x[0] for x in comp_mu), 2):.2f}–{down(max(x[1] for x in comp_mu), 2):.2f}. "
        f"Off the axis the pole traction falls as C44 falls: on a bare-lattice cell the tension half's averaged traction "
        f"reaches p₀ at the source day's strain on every install angle once the Zener ratio exceeds "
        f"{f'{up(max(zstar_fin), 3):.3f}' if zstar_fin else 'none'}, against the Voigt ceiling {up(a_voigt, 3):.3f}; no "
        f"measured C44 is used. At 106's binding "
        f"cell (the union's lowest θ = 0 share, {bind_clause}. At the union's C44 → 0 supremum, a bare-lattice cell, the "
        f"in-plane stress is "
        f"{'isotropic — the bending field puts no averaged in-plane shear there, which is no holding claim' if sup['in_plane_stress_isotropic'] else 'anisotropic'}"
        f"; its tension half opens {jn_clause(sup)}; on the published sets only (the founder-ratified companion) its "
        f"averaged traction reaches p₀ {jn_clause(sup_pub)} (below p₀ elsewhere — no holding claim). With tissue in the macropores (01_04 §2, Phase 2) the lattice interlocks with it: the "
        f"envelope traction is then the demand on that composite, and neither failing nor holding follows from it; the "
        f"anode's axial bond force also moves σ_n through the gyroid's Poisson strain, with a sign that alternates with "
        f"the sway, and what that, opening, slip and interlock do to the share is not computed."
    )

    result = {
        "script": "108",
        "question": "00_07 HW.23 — 106's bonded interface read as a pressed frictional contact: the friction it needs, "
                    "where it opens and the growth pressure needed to keep it closed (step 1, a validity map)",
        "inputs": {
            "share_106": "mechanical/gyroid_wood_strain_share.json — its lattice reading, grids and the cells of both its "
                         "groups; σᴵ is not in it, so it is recomputed here with 106's functions (importlib, no main()) "
                         "and the shares held to every cached cell of both groups",
            "groups": {"scots_pine": "106's unsuffixed keys (cells · wood_readings)",
                       "green": "106's green_* keys (green_cells · green_wood_readings)",
                       "union": "both groups; the binding claim and the junction ceiling as 106's consumer blocks name "
                                "them"},
            "upstream_fingerprint": {"106": {"sha256": fingerprint(d106, CONSUMED_106), "fields": list(CONSUMED_106)},
                                     "105": {"sha256": fingerprint(d105, CONSUMED_105), "fields": list(CONSUMED_105)},
                                     "cem_anode": {"sha256": fingerprint(cem, CONSUMED_CEM), "fields": list(CONSUMED_CEM),
                                                   "file": str(CEM_ANODE.relative_to(REPO_ROOT))}},
            "lattice_reading_106": {"C11_over_E_s": c11, "C12_over_E_s": c12, "zener_voigt_ceiling": a_voigt},
            "solid_fraction_105": phi,
            "theta_deg_106": list(theta),
            "zener_grid_106_with_zero": a_list,
            "p0_source": BRUDER,
            "p0_readings": P0_READINGS,
            "p0_excluded": P0_EXCLUDED,
            "p0_further_on_the_pages": P0_FURTHER_ON_THE_PAGES,
            "p0_domain": "ROOT growth pressure (poplar roots and root cells) — no primary found in reach (2026-10-22) "
                         "measures a conifer's stem callus pressing on an inclusion; p₀ taken uniform, sustained and "
                         "shear-free (OUR reading); neither p₀ nor μ is picked — each statement prints the p₀ it needs",
            "strain_source": "105's cache: stem_readings_87 (87's source day — one Scots pine, DBH 21.5 cm, one January "
                             "day) × depth_fraction",
            "strain_at_gyroid_ue": strains,
            "strain_ends": {"low": LOW_END, "high": HIGH_END},
            "sign_convention": "σ_n tension positive; contact pressure p₀ − σ_n; opening where σ_n ≥ p₀; s = +1 the "
                               "wood at the anchor in tension (windward), −1 in compression (leeward)",
            "voigt_order": list(VOIGT_ORDER),
            "p0_list_order": list(P0_NAMES),
        },
        "reproduction_of_106": {"cells": {g: len(d106[GROUPS_READ[g][0]]) for g in GROUPS_READ},
                                "fields": ["t_L_theta0_any_C44", "t_L_at_voigt_C44_min_over_theta",
                                           "t_L_at_voigt_C44_max_over_theta", "t_L_at_C44_zero_max_over_theta",
                                           "theta_of_min_deg", "theta_of_max_at_C44_zero_deg"],
                                "worst_relative": repro},
        "controls": {"groups_unread": unread,
                     "isotropic_closed_form_traction_max_error": ctl_iso,
                     "axial_shear_over_stress_worst": axial_worst,
                     "projection_vs_mohr_circle_worst": mohr_worst,
                     "theta0_sigma_moves_with_C44_worst": c44_free_worst,
                     "sigma1_drop_as_C44_rises_worst": s1_drop_worst,
                     "mu_tangent_vs_brute_force_worst": brute_worst,
                     "mu_onset_fraction_form_vs_half_map_worst": lam_worst},
        "cells": {k: out_cells[k] for k in keys_of["scots_pine"]},
        "green_cells": {k: out_cells[k] for k in keys_of["green"]},
        "summary": summary,
        "summary_bare_lattice": summary_bare,
        "p0_excluded_price": excluded_price,
        "consumer_binding_106_theta0": binding,
        "consumer_junction": junction,
        "axial_anode_bond_force_105": axial,
        "psi_resolution": psi_resolution,
        "homogenisation": "the traction is the average over the cut lattice on the envelope; for a SMOOTH contact whose "
                          "local normal is the envelope's, full stick needs |τ_loc| ≤ μ·p_loc at every point, so μ_req "
                          "of the averages is a lower bound on the friction it needs and an averaged opening forces a "
                          "local one — that contact can be shown failing, never holding. A contact that is not smooth "
                          "has no guaranteed direction (an inclined facet carries averaged shear with zero friction, an "
                          "undercut one averaged tension under positive pressure), and with tissue in the macropores "
                          "(01_04 §2, Phase 2) the envelope is crossed by an interlocked composite: the traction is its "
                          "demand, and neither failing nor holding follows. On a Voigt cell σᴵ is a bound tensor's "
                          "stress, not the average of an admissible local traction. So the smooth-contact statements "
                          "are taken over the bare-lattice cells (`summary_bare_lattice`); `summary` over all cells is "
                          "the demand, and a field named «opens» there means the averaged traction reaches p₀",
        "not_computed": [
            "the unbonded and the interlocked ends — slip with the normal contact kept, opening, and the internal Ti–tissue "
            "faces of an interlock — and what each does to t_L (the leg's step 2: a slipping interface keeps no uniform "
            "field in an anisotropic matrix)",
            "the traction on the ligament ends and on the ligament surfaces inside the pores (the homogenised traction "
            "is their average), and the O(cell/radius) error of that average",
            "the Ø15 interface, callus against the old wood of the drilled wall — no interface in 106's model",
            "p₀ for a conifer's stem callus, its distribution around the gyroid and its relaxation",
            "the finite length: the ends' axial shear and the anode bond force's distribution along the gyroid",
            "C44, the tissue's stiffness, the bark and S5 — as in 106",
            "the change of σ_n the anode's axial bond force makes through the gyroid's Poisson strain (its sign alternates "
            "with the sway), so the axial force's net effect on the friction needed",
        ],
        "verdict": verdict,
    }
    OUT.write_text(dump_compact(result) + "\n", encoding="utf-8")

    print(f"  reproduction of 106's cells ({result['reproduction_of_106']['cells']}): worst relative {repro:.1e} · "
          f"controls: isotropic {ctl_iso:.1e} · axial {axial_worst:.1e} · Mohr {mohr_worst:.1e} · θ = 0 vs C44 "
          f"{c44_free_worst:.1e} · σ₁ drop {s1_drop_worst:.1e} · μ tangent {brute_worst:.1e} · λ-form {lam_worst:.1e}")
    print("  source day at the gyroid: " + " · ".join(f"{k} {v:.0f} µε" for k, v in strains.items()))
    for grp in GROUP_ORDER:
        sm = summary[grp]
        print(f"  ── {grp} ({sm['cells']} cells, {sm['bare_lattice_cells']} bare lattice)")
        for h, _ in HALVES:
            print(f"    θ = 0 {h:11s} opens above: " + " · ".join(
                f"{n} {on['range'][0]:.0f}–{on['range'][1]:.0f} µε" + (f" ({on['cells_never']} never)"
                                                                      if on['cells_never'] else "")
                for n, on in sm["theta0"]["opening_onset_ue"][h].items()))
            print(f"    θ = 0 {h:11s} p₀ to stay closed: " + " · ".join(
                f"{ek} {v[0]:.2f}–{v[1]:.2f} MPa" for ek, v in sm["theta0"]["p0_to_stay_closed_MPa"][h].items()))
            for end in ("low", "high"):
                for n, v in sm["theta0"]["at_source_day"][h][end].items():
                    mu = v["mu_req_max_closed"]
                    print(f"      {end:4s} {n:30s} open {v['cells_open']:3d}/{v['cells']} (bare "
                          f"{v['bare_lattice_cells_open']}) share {v['open_share'][0]:.2f}–{v['open_share'][1]:.2f} · "
                          f"μ_req " + (f"{mu[0]:.2f}–{mu[1]:.2f}" if mu else "—"))
        print("    grid: tension onset " + " · ".join(
            f"{n} {v[0]:.0f}–" + ("never" if v[1] is None else f"{v[1]:.0f}") + " µε"
            for n, v in sm["grid"]["opening_onset_tension_ue"].items())
              + f" (lowest σ₁ at {sm['grid']['sigma1_min_cell']})")
        for end in ("low", "high"):
            print(f"    grid ({end} end): Zener above which the tension half opens on every angle: " + " · ".join(
                f"{n} {v['max'] if v['max'] is None else round(v['max'], 4)} ({v['cells_opening_at_every_ratio']} never)"
                for n, v in sm["grid"]["zener_above_which_tension_half_opens_on_every_angle"][end].items()))
            print(f"    grid ({end} end): compression half " + " · ".join(
                f"{n} open {v['states_open']}/{v['states']} μ {v['mu_req_max_closed']}"
                for n, v in sm["grid"]["compression_half"][end].items()))
        print("    θ = 0 μ_req at half the onset (p₀-free): " + " · ".join(
            f"{h} {v[0]:.3f}–{v[1]:.3f}" for h, v in sm["theta0"]["mu_req_max_at_half_onset"].items()))
    for grp, bd in binding.items():
        for al, v in bd.items():
            print(f"  binding {grp:10s} {al:18s} {v['cell'].split('|', 1)[1]:52s} threshold {v['threshold_ue_106']} · "
                  "onset " + " · ".join(f"{x:.0f}" for x in v["opening_onset_tension_ue"])
                  + f" µε · ≥ {v['threshold_over_onset_min']:.2f}× · p₀ to stay closed "
                  + " ".join(f"{x:.2f}" for x in v["p0_to_stay_closed_at_threshold_MPa"].values()))
    for grp, jn in junction.items():
        sp = jn["sup_C44_zero"]
        print(f"  junction sup {grp:10s} {sp['cell']} θ {sp['theta_deg']}: t_L {sp['t_L']:.3f} · σ₁ "
              f"{sp['mohr']['sigma1']:.1f} σ₂ {sp['mohr']['sigma2']:.1f} · open at {sp['tension_half_open_at']}")
    sp = junction[UNION]["sup_C44_zero_published_sets_only"]
    print(f"  junction sup union, published sets only: {sp['cell']} θ {sp['theta_deg']}: t_L {sp['t_L']:.3f} · σ₁ "
          f"{sp['mohr']['sigma1']:.1f} · onset {sp['opening_onset_tension_ue']} · open at {sp['tension_half_open_at']}")
    for grp in GROUP_ORDER:
        sm = summary_bare[grp]
        print(f"  bare {grp:10s} ({sm['cells']} cells): need {sm['theta0']['p0_to_stay_closed_MPa']['tension'][LOW_END]}"
              " · tension onset " + " · ".join(f"{n} {v['range']}" for n, v in
                                               sm["theta0"]["opening_onset_ue"]["tension"].items()))
        print(f"    excluded {excl} MPa: {excluded_price[grp]}")
    for tag, row in margin_rows.items():
        print(f"  ψ margin ({tag} period {row['period_mm']} mm): patch need {row['patch_need_MPa']:.3f} MPa · margin "
              f"{row['margin_over_higher_p0']:.3f} · arc {row['cell_arc_rad']:.3f} rad · constant below "
              f"{row['constant_below_which_every_bare_cell_still_opens']:.3f} ({row['tightest_bare_cell']})")
    for k, v in axial["states"].items():
        print(f"  axial {k:45s} {v['force_N']:7.1f} N · τ̄_R over the envelope {v['mean_shear_MPa']:.3f} MPa")
    print(f"  → {OUT.relative_to(REPO_ROOT)}")
    print(f"  {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
