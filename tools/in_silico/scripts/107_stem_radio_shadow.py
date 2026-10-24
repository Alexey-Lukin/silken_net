#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""107 — how deep the tree's own stem shadows the node's 868 MHz radio, by the azimuth between the node's face and
the gateway (00_07 HW.6, the leg «тінь стовбура за азимутом — модель до польового розрізу»; exact series, no mesh).

WHY. The ⚖️ mounting-azimuth verdict (00_07 HW.6) stands on axes that pull apart: frost ⊥ sun under the flange is
computed (`79`), and the stem's own shadow towards the gateway had only a field cut planned (UNI.10 (b)) — 01_04 §3.1
says the radio axis is not computed. This is the desk model of that axis: the FORM of the loss against azimuth and its
ORDER. It is a model, not a measurement; the field cut stays the judge.

MODEL. Two-dimensional and exact inside its idealization: an infinite line source parallel to the axis of an infinite
circular stem of concentric lossy layers (heartwood · sapwood · bark, from the axis out), in air. Time convention
e^{jωt}; a lossy layer has ε = ε′ − jε″ and Im k < 0. The source's wave is expanded about the stem's axis by Graf's
addition theorem; inside each layer the field is A·[J_n(kρ) + R·Y_n(kρ)], and the layers are matched outward through
one admittance recursion Γ = p·f′/f, continuous across every interface (TM: E_z and ∂E_z/∂ρ, p = 1; TE: H_z and
(1/ε_r)·∂H_z/∂ρ, p = 1/ε_r); the scattered coefficient outside is c_n = −H_n(βρ′)·[βJ_n′(βa) − ΓJ_n(βa)] /
[βH_n′(βa) − ΓH_n(βa)]. Two polarizations are named readings, never a pick (in-silico §When Modifying #11):
  TM — an electric line current along the stem: E parallel to the stem (a dipole along the stem — co-polar with the
       gateway's vertical antenna, so the uplink's co-polar shadow is TM's at ANY clocking of the board);
  TE — a line of electric dipoles TANGENTIAL to the bark: E horizontal (the board lies on the bark, so its ground current
       runs along the stem or across it; a loop with its axis along the stem would need radial current and is not a
       source this board can form).
Two outputs, and they differ in what they are worth. |F(φ)|² is the far field at azimuth φ with the tree against the
same source CURRENT without it (free space: |F| ≡ 1). For a short dipole (TM) or a small loop (TE) along the stem
beside an infinite stem this is EXACT in the horizontal plane, not only in 2-D: the far field at elevation θ selects
the axial wavenumber k_z = β·cosθ, and at θ = 90° (k_z = 0) the TM and TE problems decouple into precisely this 2-D
one — so the SHAPE of the shadow against azimuth, G(φ) − G(0), is the horizontal-plane cut of the 3-D problem (a
gateway low over the horizon). G(φ) = |F(φ)|² / (P_in/P₀) is the same field for the same INPUT power — it carries
what the stem absorbs and how it changes the source's radiation resistance — and its normalisation is 2-D: a finite
antenna's input power integrates over every k_z, so G(0) and the efficiency are INDICATORS of the near-field loss,
not the 3-D antenna efficiency (that number belongs to the antenna measurement, 00_07 HW.17). φ = 0 is the bearing
from the stem's axis through the node (the gateway in front of the node); φ = 180° the bearing straight through it.
  P_in/P₀ = 1 + Re Σ c_n·H_n(βρ′)  (the reaction of the scattered field on the source)
  P_rad/P₀ = Σ |J_n(βρ′) + c_n|²    (Parseval over the far field)
  P_abs/P₀ = (π/2)·β²·ε″·Σ∫|f_n|²ρdρ (TM) · (π/2)·(ε″/|ε_r|²)·Σ∫(|f_n′|² + n²|f_n|²/ρ²)ρdρ (TE), per layer.

CONTROLS (runtime gates, NaN-safe; each CAN fail — in-silico §When Modifying #8):
  free space — every layer at ε_r = 1 must return the free source's field (catches a coefficient that does not vanish
    without a scatterer);
  lossless — the operating geometry with ε″ = 0 must return P_in = P_rad (catches a wrong reaction term or broken power
    bookkeeping; ⚠️ ANY real admittance conserves energy, so it does not discriminate a wrong matching);
  energy balance — on EVERY lossy row, P_in − P_rad must equal the power dissipated INSIDE, integrated by quadrature
    over the interior field, whose amplitudes come from value continuity inward and not from c_n's formula (catches
    a wrong matching, an interior amplitude or a layer's R that the exterior coefficients alone would not expose);
  truncation — the series at N and at N + 15 must agree (catches a cut-off that clips the source's spectrum);
  width sweep — the sweep's rows at the three NAMED widths must equal the named readings' rows field by field (catches a
    sweep that builds its stem differently from the readings it extends; it CANNOT catch an extreme between two grid
    widths — the step is the ground there, see WIDTH SWEEP);
  DBH sweep — its rows at the three NAMED stems must equal the width sweep's rows field by field (catches a bark
    interpolation that misses the table, or a stem built differently); the standoff's monotonicity is COUNTED, not
    asserted — the count refuted the claim (DBH SWEEP).
WIDTH SWEEP (00_07 HW.6; the adversarial review of 2026-10-22, F1). The sapwood width acts RESONANTLY: wet sapwood at
Mavrovic's thawed ε has an in-medium wavelength λ₀/Re√ε ≈ 7.8 cm at the carrier (`width_sweep.sapwood_wavelength_cm`),
so every output swings up and down as the width grows, about every λ/2 ≈ 3.9 cm. Named widths bracket an output only
where it is monotone between them, so no set of named widths can name a consumer's worst case; the sweep runs the
three-layer Scots stem (dead bark · sapwood at the thawed ε · heartwood at the dry proxy) over the MEASURED width axis,
2.2–13.6 cm in 0.2 cm steps (≈ λ/39) plus the three named widths, under every bark, stem, standoff and polarization the
readings run, and writes each consumer's extreme with the width, bark, stem and standoff that produce it. The axis ends:
2.2 cm is Björklund 1999's narrowest stem (Table 2, p. 123, CT at 3.5–4.5 m); the wide end is the widest per-radius
staining width of Bieker & Rust 2010 Fig. 2 (p. 269, read from the page image: 18 radii, staining ≈ 4.0–13.4 cm, ERT
≈ 3.8–11.6 cm at 0.3 m), carried to 13.6 cm; Björklund's widest stem, 90 mm, lies inside. The sweep's rows skip the
N + 15 truncation re-solve (the series order depends on βρ′ alone, which the sweep does not change; the named
readings run it at every stem and standoff) and keep the energy balance.
DBH SWEEP (00_07 HW.6; the review of the width sweep, F1, 2026-10-22 night). The stem's diameter is the second resonant
axis: the three named stems are three points, and `run_case` at DBH 54 cm sat on the ratified rule's edge between them.
So the sweep runs the stem from canon's smallest host (lib DBH_MIN_CM, 38 cm) to its largest (lib DBH_MAX_CM, 60 cm —
the end of 01_04 §3.2's bark table, ⚖️ 2026-10-24) in 1 cm steps, under every width of the width axis, every bark,
both standoffs and both polarizations — the
dead bark at each stem DERIVED by linear interpolation between the table's three stems (not a reading); past 60 cm the
table ends, so a PROBE to 90 cm runs the TM «phloem» stem under THREE bark assumptions, each carried as one (the thin end
held at 22 mm · the thin end extended by the table's 50→60 slope · the thick end extended likewise), under both standoffs.
The standoff was EXPECTED monotone (a length ≪ λ, its adverse end at the bottom) and is NOT for TM over the grid: the
sweep counts, per polarization, the (stem × width × bark) cells whose −3 dB crossing is narrower at the HIGHER deck — a
minority for TM (every TM row at the sector's floor sits at the low deck), every cell for TE (the higher deck is TE's
adverse end). What it writes:
each consumer's extreme over the whole (stem × width × bark × standoff) grid with the rows that attain it, the per-stem
envelope, the TM 3-dB sector's floor per stem and bark, the −3 dB CROSSING on the 1° report grid interpolated linearly
(`crossing_3dB_deg` — a smooth output the step grounds; the integer sector is its floor), and whether the ratified ±50°
rule holds on the 1° grid with its margin. CANNOT catch an extreme between two grid stems or widths (the step is the
ground), and the probe beyond 60 cm stands on an assumed bark.
BARK SWEEP (00_07 HW.6; the DBH sweep's review, 2026-10-23 evening). The dead bark is the THIRD resonant length: at the
«phloem» reading (ε ≈ 19.4) the in-medium wavelength is ≈ 7.8 cm, and canon's dead bark runs 13.5–21 mm at DBH 38 and
17.5–28 mm at DBH 50 (01_04 §3.2 — single bark on the ridges less the live phloem: ≤ 3 mm at the thin end as canon says,
and ≈ 1 mm at the thick end as OUR reading of canon's own pattern there — 21 = 22 − 1 at 38, 28 = 29 − 1 at 50 — an
assumption canon does not state), so the bark is not ≪ λ and the DBH sweep's THIN end was one end of an axis, not the axis. The sweep runs the
TM «phloem» stem at every stem of the DBH axis, every width of the width axis, both decks and the bark from the thin to
the thick end in 1 mm steps (both ends per stem derived by linear interpolation between the table's stems; DBH 60's thick
end 35 mm is the same rule applied to the table's 25–36 mm), the dry and wet proxies at the thick end only (their floors
stay above the rule at both ends — the DBH sweep's `tm_sector_floor_by_bark` at the thin end,
`thick_end_dry_wet` at the thick); identity control against the DBH sweep's rows at the thin end; the rule block over the whole bark
axis; the floor rows re-solved under the four single-reading A.36 interpolations (the crossing's span under the bark
reading). The probe past the table carries THREE bark assumptions — the thin end held at 22 mm, the thin end extended
by the table's 50→60 slope, the thick end extended likewise — each labelled an assumption, and the rule is reported per
assumption. CANNOT catch a bark between two 1 mm steps, a thicker bark than canon's table or a furrow (the table is
ridge-referenced).
NOT guarded at runtime: the far field's ORIENTATION (a swap of front and back, (−j)^n for j^n, passes every gate — the
invariants test's direct closed form catches it) and the per-layer split of the absorbed power. CANNOT catch a wrong
INPUT — a permittivity, a radius or a standoff — nor anything the 2-D idealization drops.

CANNOT (declared ceilings): (1) the third dimension beyond the horizontal cut — a finite and tapering stem, the ground
and its reflection, a gateway high above the horizon (k_z ≠ 0, where a dielectric stem couples TM and TE); and the
absolute 3-D level — G(0) and the efficiency are 2-D indicators;
(2) the node's own body — the titanium flange, the PEEK radome and, above all, the ANCHOR: the board's ground (the
booster's radiator) is tied through the centre pogo to the Ø1.0 Ti bus, which runs about 93 mm RADIALLY into the wet
stem to the gyroid (02_02 §1.2, 02_01 §5.3 — no RF choke in canon). A radial conductor in lossy wood is no line source
along the axis and no layer; it may move the absolute level and, possibly, the front-to-back ratio, and nothing here
bounds by how much; (3) the antenna's real polarization and pattern — the booster's ground-mode current lies in the board
plane, and how that plane's diameter is clocked against the stem is uncontrolled in canon (the anchor rotates freely at
install — its anti-rotation key is cut, 01_01 §4.3 C), so TM ⊥ TE is a bracket; a dipole normal to the bark, the
booster's 8–10 mm offset from the anchor's axis and the cross-polar loss against the gateway's vertical antenna are not
modelled; (4) the canopy, other stems and the forest's excess path loss; (5) the permittivity at 868 MHz — no source
in the tree measures it there: the readings are named in READINGS with their sources and derivations, and the frozen
stem is a reading of its own; each layer is isotropic, while wood is not — a TM source sees ε along the grain and the
in-situ probe read a mixed face (lab spruce puts ε′∥/ε′⊥ at 2.2–2.4, Reci 2016), so the longitudinal ε a TM node sees
may be higher than every reading here; and the wettest bark swept here is a conifer's trunk bark read off El-Rayes &
Ulaby 1987, Fig. A.36 (balsam fir, lab, ≈ 19.4 − j4.7 — interpolated between grid markers whose frequencies are inferred
from a dry branch's figures, not measured at 868 MHz); a wetter bark is not swept, and that this bark is dominated by its
wet phloem is OUR hypothesis (ground: the Franchois 1998 abstract on two other conifers) — the figure's title says only
trunk bark; and the sapwood's WIDTH is read at the sources' heights, not at the node's (canon assumes one without
fixing it: 03_03 reads the stem «на висоті грудей», 01_02 bounds the mount «≤ 2.0 м»): Bieker & Rust 2010 at 0.3 m
above ground give the MEANS over 18 radii of one quantity by two methods — staining 8.1 ± 0.6 cm ⊥ resistivity
tomography 6.1 ± 0.5 cm, an SE-like spread beside Fig. 2's per-radius range — and both means are named readings, the
2 cm between their boundaries carried wet ⊥ dry; Björklund 1999's narrowest stem, 22 mm, is a width at 3.5–4.5 m. On
his two-stand examples the sapwood was widest at the butt and rather constant above 3 m, so below 3 m a given stem's
sapwood is LIKELY, not established, to be wider than that figure (his own Introduction cites sapwood width as
relatively constant along the trunk). The width axis itself is swept (WIDTH SWEEP), so height gives no consumer a
direction; (6) a stem that is not round, a node not on a radius, the radial profile inside a layer (each layer is
uniform).

Run:  conda activate silken_md
      python tools/in_silico/scripts/107_stem_radio_shadow.py
"""
from __future__ import annotations

import itertools
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from scipy.integrate import quad
from scipy.special import h2vp, hankel2, jv, jvp, yv, yvp

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BARK_DEAD_RIDGE_DBH38_MM,
    BARK_SINGLE_RIDGE_MM_BY_DBH_CM,
    CACHE_DIR,
    DBH_MAX_CM,
    DBH_MIN_CM,
    LIVE_PHLOEM_MM_THICK_END_READING,
    LIVE_PHLOEM_MM_THIN_END,
    REPO_ROOT,
)
from lib.utils import banner

SI_DESCRIPTION = ("Radio shadow of a tree stem at 868 MHz: the exact two-dimensional cylindrical-wave solution for a "
                  "line source beside a layered lossy circular stem (heartwood, sapwood, bark), giving the azimuthal "
                  "field against the same source in free space at equal current (the horizontal-plane cut of a short "
                  "dipole or loop along an infinite stem) and at equal input power (a two-dimensional indicator of the "
                  "near-field loss), for both polarizations as a bracket of readings, with free-space, lossless, "
                  "energy-balance and truncation controls")

CEM_DIR = REPO_ROOT / "tools/cad/cem"
OUT_DIR = CACHE_DIR / "radio"
OUT = OUT_DIR / "stem_radio_shadow.json"
C0 = 299_792_458.0
PHY_HEADER = REPO_ROOT / "firmware/common/lora_phy.h"
F_HZ = float(re.search(r"#define\s+LORA_PHY_FREQ_HZ\s+(\d+)u", PHY_HEADER.read_text(encoding="utf-8")).group(1))
# ↑ the radio's carrier, read from the firmware's PHY (868.2 MHz, 03_05 §2.1 — «⛔ не повертати 868.0»)
PHI_DEG = np.arange(0, 181, 1)       # the pattern is symmetric about the node's radius
PHI_FINE_DEG = np.arange(0.0, 180.0001, 0.05)   # for the deepest null only
REPORT_DEG = (0, 30, 50, 60, 90, 120, 150, 180)   # 50 = the rule angle, so the loss at ±50° is a cache number, not a re-solve
TOL_FREE = 1e-12                     # |F| − 1 with every ε_r = 1 (measured ~1e-15)
TOL_LOSSLESS = 1e-10                 # relative P_in − P_rad without loss (measured ~1e-16)
TOL_BALANCE = 1e-6                   # relative miss of P_in − P_rad − P_abs(volume) (quadrature epsrel 1e-10)
TOL_TRUNC = 1e-10                    # max |ΔF| between N and N + 15


def k_of(beta: float, eps: complex) -> complex:
    """Wavenumber in a layer, on the branch with Im k ≤ 0 (e^{jωt}: a wave decaying outward)."""
    k = beta * np.sqrt(complex(eps))
    return k.conjugate() if k.imag > 0 else k


def source_coeffs(n, x, pol):
    """Expansion of the source about the stem's axis: (incident coefficient for ρ < ρ′, free-space far coefficient).
    TM — an electric line current along the stem: H_n(x), J_n(x). TE — a line of electric dipoles TANGENTIAL to the
    bark (the horizontal current a board lying on the bark can carry): the ∂/∂ρ′ of the line's expansion, H_n′(x), J_n′(x)
    (the common factor β cancels in every ratio)."""
    if pol == "TM":
        return hankel2(n, x), jv(n, x)
    return h2vp(n, x), jvp(n, x)


def solve(layers, rho_src: float, pol: str, n_max: int, f_hz: float = F_HZ):
    """Series coefficients for a line source at radius rho_src beside a layered stem.

    layers — [(outer_radius_m, eps_r complex), …] from the axis outward; the last radius is the stem's surface.
    pol — 'TM' (E along the stem) or 'TE' (H along the stem).
    Returns (beta, ns, c, interior) — interior[i] is a list of (k, R, r_in, r_out, eps, A) per layer for order ns[i]."""
    beta = 2 * math.pi * f_hz / C0
    a = layers[-1][0]
    if not rho_src > a:
        raise ValueError(f"the source sits inside the stem: rho_src {rho_src} ≤ a {a}")
    ns = np.arange(-n_max, n_max + 1)
    c = np.zeros(ns.size, complex)
    interior = []
    for i, n in enumerate(ns):
        gam, per, r_prev = None, [], 0.0
        for j, (r_out, eps) in enumerate(layers):
            k = k_of(beta, eps)
            p = 1.0 if pol == "TM" else 1.0 / complex(eps)
            if j == 0:
                R = 0j
            else:
                x = k * r_prev
                R = (gam * jv(n, x) - p * k * jvp(n, x)) / (p * k * yvp(n, x) - gam * yv(n, x))
            xo = k * r_out
            gam = p * k * (jvp(n, xo) + R * yvp(n, xo)) / (jv(n, xo) + R * yv(n, xo))
            per.append([k, R, r_prev, r_out, complex(eps)])
            r_prev = r_out
        hs, _ = source_coeffs(n, beta * rho_src, pol)
        c[i] = -hs * (beta * jvp(n, beta * a) - gam * jv(n, beta * a)) / (beta * h2vp(n, beta * a) - gam * hankel2(n, beta * a))
        val = hs * jv(n, beta * a) + c[i] * hankel2(n, beta * a)   # the field just outside the surface, inward by continuity
        for row in reversed(per):
            k, R, r_in, r_out, _ = row
            amp = val / (jv(n, k * r_out) + R * yv(n, k * r_out))
            row.append(amp)
            val = amp * (jv(n, k * r_in) + R * yv(n, k * r_in)) if r_in > 0 else None
        interior.append(per)
    return beta, ns, c, interior


def far_field(beta, ns, c, rho_src, phi_rad, pol, free=False):
    """F(φ) = Σ j^n (τ_n + c_n) e^{jnφ}; with free=True the same source with no tree (c = 0)."""
    _, tau = source_coeffs(ns, beta * rho_src, pol)
    terms = (1j ** ns) * (tau + (0 if free else c))
    return np.exp(1j * np.outer(phi_rad, ns)) @ terms


def powers(beta, ns, c, rho_src, pol):
    """(P_in, P_rad, P0) in one unit: P0 = Σ τ_n² is the same source's radiated power with no tree (1 for the line)."""
    alpha, tau = source_coeffs(ns, beta * rho_src, pol)
    p0 = float(np.sum(np.abs(tau) ** 2))
    p_in = float(p0 + np.real(np.sum(c * alpha)))
    p_rad = float(np.sum(np.abs(tau + c) ** 2))
    return p_in, p_rad, p0


def absorbed_by_layer(beta, ns, interior, pol):
    """P_abs/P₀ per layer from the INTERIOR field, by quadrature — independent of the reaction and Parseval sums."""
    out = [0.0] * len(interior[0])
    for i, n in enumerate(ns):
        for j, (k, R, r_in, r_out, eps, amp) in enumerate(interior[i]):
            epp = -eps.imag
            if epp <= 0:
                continue
            if pol == "TM":
                def g(r, n=n, k=k, R=R, amp=amp):
                    return abs(amp * (jv(n, k * r) + R * yv(n, k * r))) ** 2 * r
                val = quad(g, r_in, r_out, limit=400, epsabs=0, epsrel=1e-10)[0]
                out[j] += 0.5 * math.pi * beta ** 2 * epp * val
            else:
                def g(r, n=n, k=k, R=R, amp=amp):
                    fv = amp * (jv(n, k * r) + R * yv(n, k * r))
                    fd = amp * k * (jvp(n, k * r) + R * yvp(n, k * r))
                    return (abs(fd) ** 2 + (n * n) / (r * r) * abs(fv) ** 2) * r
                val = quad(g, max(r_in, 1e-12), r_out, limit=400, epsabs=0, epsrel=1e-10)[0]
                out[j] += 0.5 * math.pi * epp / abs(eps) ** 2 * val
    return out


def n_needed(beta, rho_src):
    x = beta * rho_src
    return math.ceil(x + 4.0 * x ** (1 / 3) + 12)


def db(x):
    return 10.0 * math.log10(x)


# ── Readings (in-silico §When Modifying #11: every uncertain input is a bracket of NAMED readings, never a pick) ──
# Each permittivity carries its source and, where it is DERIVED rather than read, the derivation. ε_r = ε′ − jε″.
# Mavrovic et al. 2018, Geosci. Instrum. Method. Data Syst. 7:195, Table 3 (read by its header): an open-ended coaxial
# probe on the L-band spectrum centred at 1.4 GHz, in situ in living trunks; «thawed» = the first 1 cm under the bark
# (sapwood ≈ 2 cm in those trees, §4.3.1), mostly end of spring, all at 15:00–18:00 local — the DAILY MINIMUM of the
# trunk's permittivity (§4.3.2: minima 15:00–17:00, the peak at night); «frozen» = the whole radial profile's average.
MAV_PROBE_CENTRE_HZ = 1.4e9
MAV_RED_PINE_THAWED = 19.38 - 6.26j       # Pinus resinosa, SIRENE
MAV_RED_SPRUCE_THAWED = 27.66 - 7.72j     # Picea rubens, NEIGE-FM — the highest ε′ of the table's conifers
MAV_RED_PINE_FROZEN = 8.80 - 3.17j        # whole-profile average, frozen
# ε″ scaled to 868 MHz as if ALL of it were ionic (constant σ, ε″ ∝ 1/f) from the probe's centre — the adverse end of
# the frequency step; the flat reading carries ε″ unchanged. Neither is measured at 868 MHz.
EPS2_IONIC_868 = MAV_RED_PINE_THAWED.imag * MAV_PROBE_CENTRE_HZ / F_HZ
PERMITTIVITY: dict = {
    "thawed_red_pine_flat": {"layers": [(None, MAV_RED_PINE_THAWED)],
                             "source": "Mavrovic 2018 Table 3, red pine thawed ε1cm, ε″ carried flat from the 1.4 GHz "
                                       "probe centre; the whole stem as sapwood"},
    "thawed_red_pine_ionic": {"layers": [(None, complex(MAV_RED_PINE_THAWED.real, EPS2_IONIC_868))],
                              "source": "Mavrovic 2018 Table 3, red pine thawed ε1cm, ε″ DERIVED ×(1.4 GHz / 868 MHz) — "
                                        "all of it read as ionic; the whole stem as sapwood"},
    "thawed_red_spruce_wet": {"layers": [(None, MAV_RED_SPRUCE_THAWED)],
                              "source": "Mavrovic 2018 Table 3, red spruce thawed ε1cm (the table's wettest conifer), "
                                        "ε″ flat; the whole stem as sapwood"},
    "frozen_red_pine_profile": {"layers": [(None, MAV_RED_PINE_FROZEN)],
                                "source": "Mavrovic 2018 Table 3, red pine frozen whole-profile average, ε″ flat"},
}
# The red pines' measured radial profile (Mavrovic 2018 Supplement Fig. S2, 26 May, 21.7 °C — transcribed from the page
# image at 300 dpi, ±0.2 on ε′ and ±0.05 on ε″; each point averages up to 10 mm ahead of the probe, §4.3.1, so the
# profile is smoothed): the 2.5 mm point 35.2 − j10.27, then from 6 mm a plateau, 14.05 − j4.82 at 14 mm (13.55 − j5.0
# at the deepest, 35.5 mm) — no dry heartwood within the probe's reach. The outer layer runs to 4.25 mm, midway between
# the 2.5 and 6 mm samples; the plateau is carried to the axis.
MAV_S2_OUTER, MAV_S2_OUTER_DEPTH_M = 35.2 - 10.27j, 0.00425
MAV_S2_PLATEAU = 14.05 - 4.82j
# Scots pine's sapwood width — two methods on the same stems at the same height, 2 cm apart IN THE MEAN (each is a mean
# over 9 trees × 2 radii with its printed ± — not an end of the width axis: Fig. 2's per-radius widths run ≈ 4.0–13.4 cm
# by staining and ≈ 3.8–11.6 cm by ERT, and the axis is swept, WIDTH SWEEP). Bieker & Rust 2010, Silva
# Fennica 44(2):267–273, doi:10.14214/sf.153 (9 trees, DBH 24–49.5 cm, near Göttingen; read in the source 2026-10-22):
# «Mean sapwood width from staining was 8.1 cm ± 0.6 cm and 6.1 ± 0.5 for the tomograms» (§3, p. 269); the electrodes
# went in «at constant height (30 cm) above ground» (§2.1, pp. 268–269) and the stained discs were cut in the
# tomography's plane (§2.2); staining is «about 28% ± 3% higher than that measured by ERT» (§4, p. 270). The source
# reads the gap as staining over-estimating the active sapwood («it is likely», §4) — moisture falls before extractives
# reach a stainable level, a premise its §1 takes from Bergström 2003 — and in the same paragraph says the resistivity
# boundary «is not just an effect of the higher water content in the sapwood» (resin, pit closure). For a PERMITTIVITY
# neither width is the wet width — the moisture border lies between them: p. 270 cites Rust (1999) for CT, the
# moisture-border method Björklund used, reading 17 % below staining, ≈ 8.1/1.17 ≈ 6.9 cm, inside 6.1–8.1 — so both are
# NAMED readings (in-silico §When Modifying #11): the 2 cm band between the
# two boundaries is carried dry (6.1 cm — the band in the heartwood proxy) ⊥ wet (8.1 cm — the band at the sapwood's ε).
# Which reading is at each end of a span over the NAMED readings, the cache names (`findings.<pol>.ends_by_reading`); which
# WIDTH is adverse for a consumer only the sweep can say (`width_sweep.extremes`), because the output is not monotone in it.
SCOTS_SAPWOOD_ERT_M = 0.061
SCOTS_SAPWOOD_STAIN_M = 0.081
SCOTS_SAPWOOD_HEIGHT_M = {"bieker_rust_2010": [0.3, 0.3], "bjorklund_1999": [3.5, 4.5]}   # where each width was read
# ⊕ the thin end: 22 mm, the narrowest of 198 stems in Björklund 1999, Silva Fennica 33(2):119–129, doi:10.14214/sf.662,
# Table 2 (p. 123: CT of fresh logs «at 3.5–4.5 m height», Sweden 57–66 °N; mean 46, widest 90 mm). CT reads the
# moisture border and the transition zone is counted as heartwood (p. 122), so it is a WET width. Its HEIGHT is the
# qualifier: «Sapwood width was biggest at the butt end of the stem, and was rather constant above 3 m height» (p. 123,
# read on the stems chosen to show the vertical variation, a sub-sample of two stands) — below 3 m a given stem's sapwood
# is LIKELY, not established, to be wider than this figure (his Introduction, p. 120, cites sapwood width as relatively
# constant along the trunk). Our hosts are bigger (his DBH-class means 244–331 mm, Table 1, and the sapwood widens with
# the class, Table 3) and further south; Bieker & Rust's two widths are at 0.3 m, near the butt.
SCOTS_SAPWOOD_THIN_M = 0.022
# No primary in the tree measures pine BARK or pine HEARTWOOD near 1 GHz, so both are read at named proxies:
#   dry end — Şahin Kol 2009, BioResources 4:1663, Table 1: P. sylvestris sapwood at 2.45 GHz, tangential, MC 12 %
#             (2.01 − j0.274) for the dead outer bark, MC 22 % (2.79 − j0.539) for the heartwood (red pine heartwood
#             holds 32 % green MC, Wood Handbook 2021 Table 4–1 — above that row);
#   wet end — El-Rayes & Ulaby 1987, NASA-CR-180096, Table 5.11: poplar trunk «bark (side)» at 1 GHz, 7.5 − j1.3.
#   phloem end — El-Rayes & Ulaby 1987, NASA-CR-180096 (NTRS 19870007960), Fig. A.36 «BALSAM FIR TRUNK (BARK)», PDF
#             p. 380 (lab, Mg = 0.268, 22 °C, session 11/5/85), re-read on its grid 2026-10-22: two independent
#             page-image readings, each interpolated between the 0.8 and 0.9 GHz markers to 0.8682 GHz, gave
#             19.38 − j4.72 and 19.48 − j4.69; their mean 19.43 − j4.705 is carried at the readings' own agreement (they
#             differ by 0.10 on ε′, 0.03 on ε″) as 19.4 − j4.7. Interpolated between the 0.8 and 0.9 GHz markers; the
#             0.8 GHz ε′ marker is depressed in that session (also on A.38/A.40); not measured at 868 MHz. «A bark
#             dominated by its wet phloem» is OUR hypothesis (ground: the Franchois 1998 abstract on two other conifers)
#             — the figure's title says only trunk bark. The grid's frequencies are NOT printed on A.36: they are
#             inferred from the same session's expanded-axis A.38/A.39 (a dry BRANCH), and the markers overlap
#             (±0.1–0.2 on ε′). The unrounded mean, the mean that skips the 0.8 GHz point and the FOUR single-reading
#             interpolations (two readers × with ⊥ without that point) are CONTROLS in the cache
#             (`controls.phloem_reading`, the floors each gives, and their span), not readings — the floors the findings
#             print hold at the mean of the two readings.
BARK_DRY, BARK_WET, BARK_PHLOEM, HEART_DRY = 2.01 - 0.274j, 7.5 - 1.3j, 19.4 - 4.7j, 2.79 - 0.539j
BARK_PHLOEM_CONTROLS = {"unrounded_mean_of_the_two_readings": 19.43 - 4.705j,
                        "skip_the_0p8_GHz_point": 19.63 - 4.68j,
                        "single_reading_0p8_to_0p9_low": 19.38 - 4.72j,
                        "single_reading_0p8_to_0p9_high": 19.48 - 4.69j,
                        "single_reading_skip_0p8_low": 19.57 - 4.71j,
                        "single_reading_skip_0p8_high": 19.69 - 4.64j}
# Dead bark by stem (thin ends): DBH 38 — lib's ridge bracket; DBH 50 · 60 — 01_04 §3.2's single bark (20.5 · 25 mm)
# less the ≤ 3 mm live phloem (derived). The thick end is BARK_THICK_T_M (BARK SWEEP).
BARK_T_M = {cm / 100.0: (s[0] - LIVE_PHLOEM_MM_THIN_END) / 1000.0 for cm, s in BARK_SINGLE_RIDGE_MM_BY_DBH_CM.items()}   # lib's table less canon's phloem
assert BARK_T_M[DBH_MIN_CM / 100.0] == BARK_DEAD_RIDGE_DBH38_MM[0] / 1000.0
_BARK_PROXY = {"bark_dry": "bark dry proxy", "bark_wet": "bark wet proxy",
               "bark_phloem": "bark phloem proxy: El-Rayes & Ulaby A.36 balsam-fir trunk bark, interpolated to 868 MHz; "
                              "phloem-dominated is our hypothesis"}
for _bark, _be in (("bark_dry", BARK_DRY), ("bark_wet", BARK_WET), ("bark_phloem", BARK_PHLOEM)):
    PERMITTIVITY[f"red_pine_profile_{_bark}"] = {
        "layers": [(BARK_T_M, _be), (MAV_S2_OUTER_DEPTH_M, MAV_S2_OUTER), (None, MAV_S2_PLATEAU)],
        "source": f"dead bark by stem ({_BARK_PROXY[_bark]}) · Mavrovic 2018 Fig. S2: the outer "
                  "layer, then the plateau carried to the axis"}
    PERMITTIVITY[f"scots_sapwood_6cm_{_bark}"] = {
        "layers": [(BARK_T_M, _be), (SCOTS_SAPWOOD_ERT_M, MAV_RED_PINE_THAWED), (None, HEART_DRY)],
        "sapwood_width_m": SCOTS_SAPWOOD_ERT_M, "width_read_at_height_m": SCOTS_SAPWOOD_HEIGHT_M["bieker_rust_2010"],
        "source": f"dead bark by stem ({_BARK_PROXY[_bark]}) · sapwood 6.1 cm (Bieker & Rust "
                  "2010, ERT at 0.3 m — the band to the staining boundary in the heartwood proxy) at Mavrovic's "
                  "thawed ε1cm · heartwood at the dry proxy"}
    PERMITTIVITY[f"scots_sapwood_8cm_{_bark}"] = {
        "layers": [(BARK_T_M, _be), (SCOTS_SAPWOOD_STAIN_M, MAV_RED_PINE_THAWED), (None, HEART_DRY)],
        "sapwood_width_m": SCOTS_SAPWOOD_STAIN_M, "width_read_at_height_m": SCOTS_SAPWOOD_HEIGHT_M["bieker_rust_2010"],
        "source": f"dead bark by stem ({_BARK_PROXY[_bark]}) · sapwood 8.1 cm (Bieker & Rust "
                  "2010, benzidine staining at 0.3 m — the band to the ERT boundary at the sapwood's ε) at Mavrovic's "
                  "thawed ε1cm · heartwood at the dry proxy"}
    PERMITTIVITY[f"scots_sapwood_2cm_{_bark}"] = {
        "layers": [(BARK_T_M, _be), (SCOTS_SAPWOOD_THIN_M, MAV_RED_PINE_THAWED), (None, HEART_DRY)],
        "sapwood_width_m": SCOTS_SAPWOOD_THIN_M, "width_read_at_height_m": SCOTS_SAPWOOD_HEIGHT_M["bjorklund_1999"],
        "source": f"dead bark by stem ({_BARK_PROXY[_bark]}) · sapwood 2.2 cm (Björklund 1999's "
                  "narrowest stem, CT at 3.5–4.5 m — above 3 m, where his sapwood is narrower than at the butt) at "
                  "Mavrovic's thawed ε1cm · heartwood at the dry proxy"}
GEOMETRY: dict = {}              # filled in main() from lib and the CEM (drift-proof), each with its referent
# WIDTH SWEEP (docstring): the measured axis — Björklund 1999's narrowest stem to past Bieker & Rust 2010 Fig. 2's widest
# per-radius staining width (≈ 13.4 cm) — in steps ≪ λ/2 of the wet sapwood, plus the three named widths
SWEEP_W_LOW_M, SWEEP_W_HIGH_M, SWEEP_STEP_M = SCOTS_SAPWOOD_THIN_M, 0.136, 0.002
SWEEP_BARKS = {"bark_dry": BARK_DRY, "bark_wet": BARK_WET, "bark_phloem": BARK_PHLOEM}
SWEEP_KEYS = ("front_minus_back_dB", "front_minus_side_dB", "within_3dB_of_front_to_deg", "crossing_3dB_deg",
              "deepest_below_front_dB", "phi_min_deg", "efficiency")
# DBH SWEEP (docstring): canon's smallest host to its largest (the end of 01_04 §3.2's bark table), 1 cm; the probe beyond
DBH_SWEEP_LOW_CM, DBH_SWEEP_HIGH_CM, DBH_SWEEP_STEP_CM = int(DBH_MIN_CM), int(DBH_MAX_CM), 1
DBH_BEYOND_HIGH_CM = 90
RULE_SECTOR_DEG = 50     # the ratified azimuth rule — the face within ±50° of the gateway's bearing (01_04 §3.1 ⚖️ 2026-10-22)
# The THICK end of the dead bark per named stem (BARK SWEEP): 01_04 §3.2 gives ≈ 21 mm at DBH 38 and ≈ 28 at DBH 50 (the
# single bark's ridge maximum less ≈ 1 mm of live phloem at the thick end — the subtraction is OUR reading of canon's
# pattern, an assumption); DBH 60 — the same rule on the table's 36 mm (DERIVED, canon states no dead-bark figure there).
# Both ends are ridge-referenced; furrows have no primary.
BARK_THICK_T_M = {cm / 100.0: (s[1] - LIVE_PHLOEM_MM_THICK_END_READING) / 1000.0 for cm, s in BARK_SINGLE_RIDGE_MM_BY_DBH_CM.items()}
assert BARK_THICK_T_M[DBH_MIN_CM / 100.0] == BARK_DEAD_RIDGE_DBH38_MM[1] / 1000.0
BARK_AXIS_STEP_M = 0.001


def _interp_table(table: dict, dbh_m: float, extrapolate: bool) -> float:
    pts = sorted(table.items())
    if dbh_m in table:
        return table[dbh_m]
    if dbh_m <= pts[0][0]:
        return pts[0][1]
    for (d0, t0), (d1, t1) in itertools.pairwise(pts):
        if dbh_m <= d1:
            return t0 + (t1 - t0) * (dbh_m - d0) / (d1 - d0)
    if not extrapolate:
        return pts[-1][1]
    (d0, t0), (d1, t1) = pts[-2], pts[-1]
    return t1 + (t1 - t0) * (dbh_m - d1) / (d1 - d0)


def bark_by_dbh(dbh_m: float, end: str = "thin", extrapolate: bool = False) -> float:
    """Dead bark for ANY stem at the THIN or THICK end of canon's table: the table's value at a named stem, linear between
    them (DERIVED, not a reading); beyond the table HELD at the last stem's value, or extended by the table's last slope
    when `extrapolate` — both are assumptions the beyond-table probe carries, labelled."""
    return _interp_table(BARK_T_M if end == "thin" else BARK_THICK_T_M, dbh_m, extrapolate)


def bark_axis(dbh_m: float) -> list[float]:
    """The dead bark from the thin to the thick end at this stem, in BARK_AXIS_STEP_M steps, both ends included — the
    ends EXACTLY as `bark_by_dbh` gives them (a rounded end solved a stem 0.3 µm off the DBH sweep's and failed its own
    identity control by 0.001° of crossing, 2026-10-23)."""
    lo, hi = bark_by_dbh(dbh_m, "thin"), bark_by_dbh(dbh_m, "thick")
    n_in = int((hi - lo) / BARK_AXIS_STEP_M + 1e-9)
    inner = [lo + i * BARK_AXIS_STEP_M for i in range(1, n_in + 1) if lo + i * BARK_AXIS_STEP_M < hi - 1e-9]
    return [lo, *inner, hi]
POLARIZATIONS = ("TM", "TE")
Z_STACK = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"   # `52`'s vertical stack: the RF deck over the flange
# ⛔ Not the CAD's «antenna ↔ Ti 8.0 at the bayonet datum»: that figure takes the cavity top for the antenna plane and
# so measures ROOM, not the antenna (tools/cad Validation.cs, RfClearanceMm).


def stem_layers(dbh_m: float, reading: dict):
    """[(outer_radius, eps)] from the axis out, built from a reading's bark-inward layer list; a None depth is the core.
    A depth given as a dict is read by the stem's DBH (the bark thickens with the stem — 01_04 §3.2's table)."""
    a = dbh_m / 2.0
    rows, depth = [], 0.0
    for thick, eps in reading["layers"]:
        if isinstance(thick, dict):
            thick = thick[dbh_m]
        if thick is None:
            rows.append((a - depth, eps))
            break
        rows.append((a - depth, eps))
        depth += thick
        if depth >= a:
            raise ValueError(f"layers deeper than the radius {a} m")
    return list(reversed(rows))   # axis outward; the outermost radius is the surface


def run_case(dbh_m, standoff_m, reading_name, pol, reading=None, truncation=True):
    layers = stem_layers(dbh_m, reading or PERMITTIVITY[reading_name])
    a = layers[-1][0]
    rho = a + standoff_m
    beta = 2 * math.pi * F_HZ / C0
    n = n_needed(beta, rho)
    _, ns, c, interior = solve(layers, rho, pol, n)
    phi = np.deg2rad(PHI_DEG)
    p_in, p_rad, p0 = powers(beta, ns, c, rho, pol)
    front_free = float(np.abs(far_field(beta, ns, c, rho, np.array([0.0]), pol, free=True)[0]) ** 2)
    field = np.abs(far_field(beta, ns, c, rho, phi, pol)) ** 2 / front_free   # same current, against the free front lobe
    g = field / (p_in / p0)                                                    # same INPUT power — the 2-D indicator
    # control — truncation (NaN-safe: a comparison with NaN must fail, not pass)
    trunc = math.nan
    if truncation:
        _, ns2, c2, _ = solve(layers, rho, pol, n + 15)
        trunc = float(np.max(np.abs(far_field(beta, ns, c, rho, phi, pol) - far_field(beta, ns2, c2, rho, phi, pol))))
    if truncation and not trunc <= TOL_TRUNC:
        raise RuntimeError(f"series not converged at N={n}: max|ΔF| {trunc:.2e} > {TOL_TRUNC}")
    # control — energy balance against the interior volume integral (the interior's unit is the line source's)
    by_layer = absorbed_by_layer(beta, ns, interior, pol)
    miss = (p_in - p_rad - sum(by_layer)) / p_in
    if not abs(miss) <= TOL_BALANCE:
        raise RuntimeError(f"energy balance misses by {miss:.2e} (> {TOL_BALANCE}) at {reading_name} {pol} DBH {dbh_m}")
    g_db = 10 * np.log10(g)
    # the deepest null on a fine grid — the 1° report grid misses it by up to several dB
    phi_fine = np.deg2rad(PHI_FINE_DEG)
    g_fine = 10 * np.log10(np.abs(far_field(beta, ns, c, rho, phi_fine, pol)) ** 2 / front_free / (p_in / p0))
    i_min = int(np.argmin(g_fine))
    front = float(g_db[0])
    within = [int(d) for d, v in zip(PHI_DEG, g_db, strict=True) if v >= front - 3.0]
    # the −3 dB crossing on the 1° report grid, linear between the last angle within and the first below (a smooth
    # output the step grounds; the integer sector below is its floor); 180 when the pattern never falls 3 dB
    below = [i for i, v in enumerate(g_db) if v < front - 3.0]
    crossing = 180.0
    if below:
        i = below[0]
        crossing = float(PHI_DEG[i - 1]) + (float(g_db[i - 1]) - (front - 3.0)) / (float(g_db[i - 1]) - float(g_db[i]))
    return {
        "polarization": pol, "permittivity": reading_name, "dbh_m": dbh_m, "standoff_mm": round(standoff_m * 1e3, 3),
        "layers_axis_out": [[round(r, 6), round(e.real, 4), round(-e.imag, 4)] for r, e in layers],
        "rho_src_m": round(rho, 6), "n_max": n,
        "field_same_current_dB": {str(d): round(float(10 * np.log10(field[d])), 3) for d in REPORT_DEG},
        "gain_dB": {str(d): round(float(g_db[d]), 3) for d in REPORT_DEG},
        "gain_dB_min": round(float(g_fine[i_min]), 3), "phi_min_deg": round(float(PHI_FINE_DEG[i_min]), 2),
        "front_minus_back_dB": round(front - float(g_db[180]), 3),
        "front_minus_side_dB": round(front - float(g_db[90]), 3),
        "within_3dB_of_front_to_deg": max(d for d in within if all(dd in within for dd in range(0, d + 1))),
        "crossing_3dB_deg": round(crossing, 3),
        "p_in_over_p0": round(p_in / p0, 6), "p_rad_over_p0": round(p_rad / p0, 6),
        "efficiency": round(p_rad / p_in, 5), "efficiency_dB": round(db(p_rad / p_in), 3),
        "absorbed_by_layer_axis_out": [round(x / p_in, 5) for x in by_layer],
        "controls": {"truncation_max_dF": trunc, "balance_rel_miss": miss},
    }


def controls_free_and_lossless():
    """The two controls that do not need a reading: ε_r = 1 everywhere, and the operating geometry without loss."""
    beta = 2 * math.pi * F_HZ / C0
    phi = np.deg2rad(PHI_DEG)
    worst_free, worst_lossless = 0.0, 0.0
    for pol in POLARIZATIONS:
        for layers, rho in (([(0.05, 1 + 0j), (0.14, 1 + 0j), (0.15, 1 + 0j)], 0.165), ([(0.30, 1 + 0j)], 0.31)):
            _, ns, c, _ = solve(layers, rho, pol, n_needed(beta, rho))
            worst_free = max(worst_free, float(np.max(np.abs(far_field(beta, ns, c, rho, phi, pol)
                                                              - far_field(beta, ns, c, rho, phi, pol, free=True)))))
        for layers, rho in (([(0.09, 5.0 + 0j), (0.14, 19.4 + 0j), (0.15, 3.0 + 0j)], 0.165), ([(0.30, 19.4 + 0j)], 0.31)):
            _, ns, c, _ = solve(layers, rho, pol, n_needed(beta, rho))
            p_in, p_rad, _ = powers(beta, ns, c, rho, pol)
            worst_lossless = max(worst_lossless, abs(p_in - p_rad) / p_in)
    if not worst_free <= TOL_FREE:
        raise RuntimeError(f"free-space control: max|F − F_free| {worst_free:.2e} > {TOL_FREE}")
    if not worst_lossless <= TOL_LOSSLESS:
        raise RuntimeError(f"lossless control: |P_in − P_rad|/P_in {worst_lossless:.2e} > {TOL_LOSSLESS}")
    return {"free_space_max_abs_F_minus_free": worst_free, "lossless_max_rel_power_miss": worst_lossless}


def _span(values, nd=1):
    """A range rounded OUTWARD — the reader sees no edge the cells do not reach."""
    lo, hi = min(values), max(values)
    f = 10 ** nd
    return [math.floor(lo * f) / f, math.ceil(hi * f) / f]


def _sweep_fields(r):
    """A row's consumer quantities as the findings compute them (the deepest null below the front is derived)."""
    return {k: (round(r["gain_dB"]["0"] - r["gain_dB_min"], 3) if k == "deepest_below_front_dB" else r[k])
            for k in SWEEP_KEYS}


def sweep_widths():
    """The width axis: the grid (docstring WIDTH SWEEP) plus the three named widths."""
    grid = [round(SWEEP_W_LOW_M + i * SWEEP_STEP_M, 6)
            for i in range(round((SWEEP_W_HIGH_M - SWEEP_W_LOW_M) / SWEEP_STEP_M) + 1)]
    return sorted(set(grid) | {SCOTS_SAPWOOD_THIN_M, SCOTS_SAPWOOD_ERT_M, SCOTS_SAPWOOD_STAIN_M})


def _sweep_rows(dbhs, widths, standoffs, bark_of, barks=None, pols=None, bark_eps=None):
    """The three-layer Scots stem at every (stem × width × bark × standoff × polarization): one row per solve, the dead
    bark thickness(es) at each stem from `bark_of` (a float or a list — the table at a named stem, derived elsewhere);
    `barks` the proxies to run (default all three), `pols` the polarizations, `bark_eps` an override of the bark's ε
    (the A.36 alternatives)."""
    rows = []
    for bark, be in (barks or SWEEP_BARKS).items():
        be = bark_eps if bark_eps is not None else be
        for dbh in dbhs:
            bts = bark_of(dbh)
            for bt in (bts if isinstance(bts, list) else [bts]):
                for w in widths:
                    reading = {"layers": [(bt, be), (w, MAV_RED_PINE_THAWED), (None, HEART_DRY)]}
                    for pol in (pols or POLARIZATIONS):
                        for so in standoffs:
                            r = run_case(dbh, so, f"sweep_{bark}", pol, reading=reading, truncation=False)
                            rows.append({"w_cm": round(w * 100, 2), "bark": bark, "bark_mm": round(bt * 1e3, 3),
                                         "polarization": pol, "dbh_m": dbh, "standoff_mm": r["standoff_mm"],
                                         **_sweep_fields(r)})
    return rows


def _resolve(a, eps=None, dbh_m=None, w_cm=None, bark_mm=None, standoff_mm=None, tag="resolve"):
    """A sweep row (`_ROW_AT` fields) re-solved — TM, the row's bark reading unless `eps` overrides it, any coordinate
    overridden by name; the full `run_case` result (the sweeps keep only `_sweep_fields`)."""
    eps = SWEEP_BARKS[a["bark"]] if eps is None else eps
    reading = {"layers": [((bark_mm if bark_mm is not None else a["bark_mm"]) / 1e3, eps),
                          ((w_cm if w_cm is not None else a["w_cm"]) / 100.0, MAV_RED_PINE_THAWED), (None, HEART_DRY)]}
    return run_case(dbh_m if dbh_m is not None else a["dbh_m"], (standoff_mm if standoff_mm is not None else a["standoff_mm"]) / 1e3,
                    tag, "TM", reading=reading, truncation=False)


def _loss_at_rule(r):
    """The loss at the rule angle (±RULE_SECTOR_DEG) below the front, from a `run_case` result — the letter of the rule."""
    return round(r["gain_dB"]["0"] - r["gain_dB"][str(RULE_SECTOR_DEG)], 3)


def _a36_floor_span(rows_at, key="crossing_3dB_deg"):
    """The floor rows re-solved under each single-reading A.36 interpolation (BARK_PHLOEM_CONTROLS): the span of `key`
    over the readings — what the bark READING does to a floor the mean reading sets. `key` is a sweep field, or
    `loss_at_rule_deg_dB` (the MAX over the rows is kept for it — the adverse end of a loss is the high one)."""
    out = {}
    for alt, eps in BARK_PHLOEM_CONTROLS.items():
        vals = []
        for a in rows_at:
            if a["bark"] != "bark_phloem":
                continue
            r = _resolve(a, eps=eps, tag=f"a36_{alt}")
            vals.append(_loss_at_rule(r) if key == "loss_at_rule_deg_dB" else _sweep_fields(r)[key])
        if vals:
            out[alt] = round(max(vals) if key == "loss_at_rule_deg_dB" else min(vals), 3)
    singles = [k for k in out if k.startswith("single_reading_")]
    return {"by_reading": out, "span_over_single_readings": [min(out[k] for k in singles), max(out[k] for k in singles)] if singles else None}


def _refine_floor(a, dbh_half_cm=0.5, dbh_step_cm=0.1, w_half_cm=0.2, w_step_cm=0.1, bark_half_mm=None, bark_step_mm=0.25,
                  bark_of=None, bark_bounds_of=None):
    """A finer grid around a floor row: the grid minimum is an UPPER bound on the true floor (a finer step can only find a
    lower crossing between the nodes), so the refinement reports how far below the node the floor lies on a finer step —
    not the true floor either. `bark_of(dbh_m)` derives the bark per stem (the thin-end sweep); `bark_half_mm` sweeps the
    bark itself around the row's (the bark axis), clamped per stem to `bark_bounds_of(dbh_m)` = (thin, thick) in mm with
    both ends added as nodes when they fall inside the half-range — a node past the table's edge would double the
    edge bound, not refine the floor."""
    best, n = None, 0
    dbhs = [round(a["dbh_m"] + i * dbh_step_cm / 100.0, 6) for i in range(-round(dbh_half_cm / dbh_step_cm), round(dbh_half_cm / dbh_step_cm) + 1)]
    ws = [round(a["w_cm"] + i * w_step_cm, 3) for i in range(-round(w_half_cm / w_step_cm), round(w_half_cm / w_step_cm) + 1)]
    for d in dbhs:
        if bark_of is not None:
            barks = [round(bark_of(d) * 1e3, 3)]
        else:
            barks = [round(a["bark_mm"] + i * bark_step_mm, 3) for i in range(-round(bark_half_mm / bark_step_mm), round(bark_half_mm / bark_step_mm) + 1)]
            if bark_bounds_of is not None:
                lo_b, hi_b = bark_bounds_of(d)
                barks = sorted({b for b in barks if lo_b - 1e-9 <= b <= hi_b + 1e-9} | {round(x, 3) for x in (lo_b, hi_b) if abs(x - a["bark_mm"]) <= bark_half_mm + 1e-9})
        for w in ws:
            for b in barks:
                r = _resolve(a, dbh_m=d, w_cm=w, bark_mm=b, tag="refine")
                n += 1
                cand = {"dbh_m": d, "w_cm": w, "bark_mm": b, "standoff_mm": a["standoff_mm"], "crossing_3dB_deg": r["crossing_3dB_deg"],
                        "sector_deg": r["within_3dB_of_front_to_deg"], "loss_at_rule_deg_dB": _loss_at_rule(r)}
                if best is None or cand["crossing_3dB_deg"] < best["crossing_3dB_deg"]:
                    best = cand
    return {"what": "a finer grid around the floor row — the grid minimum is an upper bound on the true floor; this is a lower "
                    "node on a finer step, not the true floor either",
            "steps": {"dbh_cm": dbh_step_cm, "w_cm": w_step_cm, "bark_mm": None if bark_of is not None else bark_step_mm},
            "n_solves": n, "min_crossing_deg": best["crossing_3dB_deg"], "at": best,
            "below_the_grid_node_deg": round(a["crossing_3dB_deg"] - best["crossing_3dB_deg"], 3) if "crossing_3dB_deg" in a else None}


_ROW_AT = ("w_cm", "bark", "bark_mm", "dbh_m", "standoff_mm")


def _at(sel, k, v):
    return [{f: r[f] for f in _ROW_AT} for r in sel if r[k] == v]


def _ext(sel):
    out = {}
    for k in SWEEP_KEYS:
        lo, hi = min(r[k] for r in sel), max(r[k] for r in sel)
        out[k] = {"min": lo, "min_at": _at(sel, k, lo), "max": hi, "max_at": _at(sel, k, hi)}
    return out


def width_sweep(cases):
    """The sapwood width over its measured axis (docstring WIDTH SWEEP): the three-layer Scots stem at every width of the
    grid and the three named widths, under every bark, stem, standoff and polarization the readings run. Returns the
    sweep's block — each consumer's extreme over the whole axis and per bark, with every row that attains it (width, bark,
    stem, standoff), the per-width envelope, and the control that the named widths reproduce the readings' rows — and
    its rows (for the DBH sweep's identity control)."""
    named = {SCOTS_SAPWOOD_THIN_M: "2cm", SCOTS_SAPWOOD_ERT_M: "6cm", SCOTS_SAPWOOD_STAIN_M: "8cm"}
    widths = sweep_widths()
    rows = _sweep_rows(GEOMETRY["dbh_m"]["values"], widths, GEOMETRY["standoff_m"]["values"], lambda d: BARK_T_M[d])
    # control — the sweep's rows at the named widths equal the named readings' rows, field by field
    worst = 0.0
    for w, tag in named.items():
        for bark in SWEEP_BARKS:
            ref = {(r["polarization"], r["dbh_m"], r["standoff_mm"]): r for r in cases
                   if r["permittivity"] == f"scots_sapwood_{tag}_{bark}"}
            got = [r for r in rows if r["w_cm"] == round(w * 100, 2) and r["bark"] == bark]
            if len(got) != len(ref) or not ref:
                raise RuntimeError(f"width-sweep control: {tag} {bark} has {len(got)} sweep rows against {len(ref)}")
            for r in got:
                c = _sweep_fields(ref[(r["polarization"], r["dbh_m"], r["standoff_mm"])])
                miss = max(abs(r[k] - c[k]) for k in SWEEP_KEYS)
                if not miss <= 0.0:
                    raise RuntimeError(f"width-sweep control: {tag} {bark} {r['polarization']} misses by {miss}")
                worst = max(worst, miss)

    extremes, by_bark, by_width = {}, {}, {}
    for pol in POLARIZATIONS:
        sel = [r for r in rows if r["polarization"] == pol]
        extremes[pol] = _ext(sel)
        by_bark[pol] = {b: _ext([r for r in sel if r["bark"] == b]) for b in SWEEP_BARKS}
        by_width[pol] = {k: [[round(w * 100, 2), min(r[k] for r in sel if r["w_cm"] == round(w * 100, 2)),
                              max(r[k] for r in sel if r["w_cm"] == round(w * 100, 2))] for w in widths]
                         for k in ("front_minus_back_dB", "front_minus_side_dB", "within_3dB_of_front_to_deg")}
    lam_cm = C0 / F_HZ / float(np.sqrt(complex(MAV_RED_PINE_THAWED)).real) * 100
    return {
        "what": "the three-layer Scots stem (dead bark · sapwood at Mavrovic's thawed ε · heartwood at the dry proxy) "
                "over the measured sapwood-width axis — the output is resonant in the width, so named widths cannot "
                "bracket it (docstring WIDTH SWEEP); rows skip the N + 15 truncation re-solve and keep the energy balance",
        "axis_cm": [round(SWEEP_W_LOW_M * 100, 2), round(SWEEP_W_HIGH_M * 100, 2)], "step_cm": round(SWEEP_STEP_M * 100, 2),
        "named_widths_cm": sorted(round(w * 100, 2) for w in named),
        "n_widths": len(widths), "n_rows": len(rows),
        "axis_ends": {"low": "Björklund 1999 Table 2 (p. 123): the narrowest of 198 stems, 22 mm, CT at 3.5–4.5 m",
                      "high": "Bieker & Rust 2010 Fig. 2 (p. 269, page image): the widest per-radius staining width, "
                              "≈ 13.4 cm at 0.3 m (ERT ≈ 11.6 cm); Björklund 1999's widest stem, 90 mm, lies inside"},
        "sapwood_wavelength_cm": round(lam_cm, 2), "half_wavelength_cm": round(lam_cm / 2, 2),
        "extremes": extremes, "by_bark": by_bark, "by_width": by_width,
        "controls": {"named_widths_reproduce_the_readings_max_abs_miss": worst},
    }, rows


def _per_dbh(rows, keys):
    """Per stem: [dbh_cm, min, max] of each key over every width, bark and standoff."""
    dbhs = sorted({r["dbh_m"] for r in rows})
    return {k: [[round(d * 100, 2), min(r[k] for r in rows if r["dbh_m"] == d), max(r[k] for r in rows if r["dbh_m"] == d)]
                for d in dbhs] for k in keys}


def _rule(sel):
    """The ratified ±RULE_SECTOR_DEG rule against the TM rows of a sweep: holds on the 1° grid, the floor of the sector
    and of the fine crossing, and the rows attaining the floor."""
    tm = [r for r in sel if r["polarization"] == "TM"]
    sec = min(r["within_3dB_of_front_to_deg"] for r in tm)
    cro = min(r["crossing_3dB_deg"] for r in tm)
    sec_at, cro_at = _at(tm, "within_3dB_of_front_to_deg", sec), _at(tm, "crossing_3dB_deg", cro)
    loss_sec = [_loss_at_rule(_resolve(a, tag="loss_at_rule")) for a in sec_at]
    return {"sector_deg": RULE_SECTOR_DEG, "holds_on_1deg_grid": sec >= RULE_SECTOR_DEG, "min_sector_deg": sec,
            "min_sector_at": sec_at, "min_crossing_deg": cro,
            "margin_deg_fine": round(cro - RULE_SECTOR_DEG, 3), "min_crossing_at": cro_at,
            # the LETTER of the rule: the loss at ±RULE_SECTOR_DEG on the crossing-floor row(s) and over the sector-floor rows
            "loss_at_rule_deg_dB": {"at_crossing_floor": [_loss_at_rule(_resolve(a, tag="loss_at_rule")) for a in cro_at],
                                    "over_sector_floor_rows": [min(loss_sec), max(loss_sec)], "n_sector_floor_rows": len(sec_at),
                                    "n_sector_floor_cells": len({(a["dbh_m"], a["w_cm"], a["bark"], a["bark_mm"]) for a in sec_at})},
            "first_stem_cm_failing_on_1deg_grid": next((round(d * 100, 2) for d in sorted({r["dbh_m"] for r in tm})
                                                         if min(r["within_3dB_of_front_to_deg"] for r in tm
                                                                if r["dbh_m"] == d) < RULE_SECTOR_DEG), None)}


def dbh_sweep(width_rows):
    """The stem's diameter over its canon axis (docstring DBH SWEEP): every stem of 38–60 cm in 1 cm steps under every
    width of the width axis, bark, standoff and polarization, the bark derived per stem (thin end); the identity control
    against the width sweep's rows at the three named stems; the standoff's monotonicity counted per polarization; the
    floor rows under the A.36 readings; and the probe beyond the bark table (61–90 cm, TM «phloem», both standoffs, three
    bark assumptions). Returns (block, rows, beyond_rows)."""
    widths = sweep_widths()
    dbhs = [round(c / 100.0, 6) for c in range(DBH_SWEEP_LOW_CM, DBH_SWEEP_HIGH_CM + 1, DBH_SWEEP_STEP_CM)]
    rows = _sweep_rows(dbhs, widths, GEOMETRY["standoff_m"]["values"], bark_by_dbh)
    # control — identity: at the three named stems these rows ARE the width sweep's, field by field
    key = lambda r: (r["w_cm"], r["bark"], r["polarization"], r["dbh_m"], r["standoff_mm"])  # noqa: E731
    ref = {key(r): r for r in width_rows}
    matched, worst = 0, 0.0
    for r in rows:
        c = ref.get(key(r))
        if c is None:
            continue
        matched += 1
        miss = max(abs(r[k] - c[k]) for k in SWEEP_KEYS)
        if not miss <= 0.0:
            raise RuntimeError(f"DBH-sweep control: {key(r)} misses the width sweep's row by {miss}")
        worst = max(worst, miss)
    if matched != len(width_rows):
        raise RuntimeError(f"DBH-sweep control: {matched} of the width sweep's {len(width_rows)} rows revisited")
    # count — the standoff's monotonicity for the sector (it was expected never to narrow as the deck rises): the cells
    # where it does; declared in the cache, and it refuted the expectation (docstring DBH SWEEP)
    lo_so, hi_so = sorted(GEOMETRY["standoff_m"]["values"])[0], sorted(GEOMETRY["standoff_m"]["values"])[-1]
    at = {key(r): r for r in rows}
    violations = [key(r) for r in rows if r["standoff_mm"] == round(lo_so * 1e3, 3)
                  and at[(r["w_cm"], r["bark"], r["polarization"], r["dbh_m"], round(hi_so * 1e3, 3))]["crossing_3dB_deg"]
                  < r["crossing_3dB_deg"]]
    sector_violations = [key(r) for r in rows if r["standoff_mm"] == round(lo_so * 1e3, 3)
                         and at[(r["w_cm"], r["bark"], r["polarization"], r["dbh_m"], round(hi_so * 1e3, 3))]["within_3dB_of_front_to_deg"]
                         < r["within_3dB_of_front_to_deg"]]
    cells_per_pol = len(rows) // len(GEOMETRY["standoff_m"]["values"]) // len(POLARIZATIONS)
    by_pol = {pol: {"cells": cells_per_pol,
                    "crossing_narrower_at_higher_deck": sum(1 for v in violations if v[2] == pol),
                    "sector_narrower_at_higher_deck": sum(1 for v in sector_violations if v[2] == pol)} for pol in POLARIZATIONS}
    extremes = {pol: _ext([r for r in rows if r["polarization"] == pol]) for pol in POLARIZATIONS}
    by_dbh = {pol: _per_dbh([r for r in rows if r["polarization"] == pol],
                            ("within_3dB_of_front_to_deg", "crossing_3dB_deg", "front_minus_back_dB", "front_minus_side_dB"))
              for pol in POLARIZATIONS}
    sector_floor = {pol: {b: [[round(d * 100, 2), min(r["within_3dB_of_front_to_deg"] for r in rows
                                                       if r["polarization"] == pol and r["bark"] == b and r["dbh_m"] == d),
                               min(r["crossing_3dB_deg"] for r in rows
                                   if r["polarization"] == pol and r["bark"] == b and r["dbh_m"] == d)] for d in dbhs]
                          for b in SWEEP_BARKS} for pol in POLARIZATIONS}
    # the probe beyond the table: THREE bark assumptions, TM on the «phloem» reading (the rule's polarization and the
    # reading that sets its floor), both standoffs (the standoff is not monotone)
    beyond_dbhs = [round(c / 100.0, 6) for c in range(DBH_SWEEP_HIGH_CM + 1, DBH_BEYOND_HIGH_CM + 1, DBH_SWEEP_STEP_CM)]
    held_mm = max(BARK_T_M.items())[1] * 1e3
    phloem_only = {"bark_phloem": SWEEP_BARKS["bark_phloem"]}
    assumptions = {
        "thin_end_held": (lambda d: bark_by_dbh(d, "thin", extrapolate=False),
                          f"the thin end HELD at the table's last value ({held_mm:g} mm)"),
        "thin_end_slope": (lambda d: bark_by_dbh(d, "thin", extrapolate=True),
                           "the thin end extended by the table's 50→60 cm slope"),
        "thick_end_slope": (lambda d: bark_by_dbh(d, "thick", extrapolate=True),
                            "the thick end extended by the table's 50→60 cm slope"),
    }
    beyond_blocks, beyond = {}, []
    for name, (fn, what) in assumptions.items():
        rws = _sweep_rows(beyond_dbhs, widths, GEOMETRY["standoff_m"]["values"], fn, barks=phloem_only, pols=("TM",))
        beyond += rws
        beyond_blocks[name] = {"what": what + " — an ASSUMPTION, not a reading", "n_rows": len(rws),
                               "bark_mm_by_dbh_cm": {str(round(d * 100, 2)): round(fn(d) * 1e3, 3) for d in beyond_dbhs},
                               "by_dbh": _per_dbh(rws, ("within_3dB_of_front_to_deg", "crossing_3dB_deg", "front_minus_back_dB")),
                               "rule": _rule(rws)}
    block = {
        "what": "the stem's diameter as an AXIS — every stem of the canon range under every width of the width axis, "
                "bark, standoff and polarization, the dead bark per stem derived by linear interpolation between the "
                "table's stems (docstring DBH SWEEP); rows skip the N + 15 truncation re-solve and keep the energy balance",
        "axis_cm": [DBH_SWEEP_LOW_CM, DBH_SWEEP_HIGH_CM], "step_cm": DBH_SWEEP_STEP_CM,
        "bark_mm_by_dbh_cm": {str(round(d * 100, 2)): round(bark_by_dbh(d) * 1e3, 3) for d in dbhs},
        "bark_named_stems_cm": sorted(round(d * 100, 2) for d in BARK_T_M),
        "widths_cm": [round(w * 100, 2) for w in widths], "standoffs_mm": sorted(round(s * 1e3, 3) for s in GEOMETRY["standoff_m"]["values"]),
        "n_stems": len(dbhs), "n_rows": len(rows),
        "extremes": extremes, "by_dbh": by_dbh, "tm_sector_floor_by_bark": sector_floor,
        "rule": _rule(rows),
        "rule_floor_refinement": _refine_floor(dict(_rule(rows)["min_crossing_at"][0], crossing_3dB_deg=_rule(rows)["min_crossing_deg"]),
                                               bark_of=lambda d: bark_by_dbh(d, "thin")),
        "controls": {"named_stems_reproduce_the_width_sweep_max_abs_miss": worst,
                     "named_stems_rows_revisited": matched,
                     "standoff_monotone_crossing_violations": len(violations),
                     "standoff_monotone_cells": len(rows) // len(GEOMETRY["standoff_m"]["values"]),
                     "standoff_monotone_by_polarization": by_pol,
                     "standoff_monotone_first_violations": [list(v) for v in violations[:5]],
                     "sector_floor_rows_all_at_low_standoff": all(a["standoff_mm"] == round(lo_so * 1e3, 3)
                                                                 for a in _rule(rows)["min_sector_at"])},
        "rule_floor_under_a36_readings": _a36_floor_span(_rule(rows)["min_crossing_at"]),
        "tm_back_floor_under_a36_readings": _a36_floor_span(extremes["TM"]["front_minus_back_dB"]["min_at"], "front_minus_back_dB"),
        "beyond_bark_table": {
            "what": f"a PROBE past the bark table: stems of {DBH_SWEEP_HIGH_CM + 1}–{DBH_BEYOND_HIGH_CM} cm on the TM "
                    f"«phloem» stem under both standoffs, the dead bark by THREE assumptions (each labelled, none a reading)",
            "axis_cm": [DBH_SWEEP_HIGH_CM + 1, DBH_BEYOND_HIGH_CM],
            "standoffs_mm": sorted(round(s * 1e3, 3) for s in GEOMETRY["standoff_m"]["values"]), "n_rows": len(beyond),
            "assumptions": beyond_blocks,
            "first_stem_cm_failing_by_assumption": {k: v["rule"]["first_stem_cm_failing_on_1deg_grid"] for k, v in beyond_blocks.items()},
            "rule": _rule(beyond),
        },
    }
    return block, rows, beyond


def bark_sweep(dbh_rows):
    """The dead bark as the THIRD resonant axis (docstring BARK SWEEP): the TM «phloem» stem at every stem of the DBH
    axis and every width, both decks, the bark from the thin to the thick end of canon's table in 1 mm steps (both ends
    derived per stem); the dry and wet proxies at the thick end only; identity control against the DBH sweep's rows at
    the thin end; the rule over the whole bark axis and the A.36 reading span of its floor rows."""
    widths = sweep_widths()
    dbhs = [round(c / 100.0, 6) for c in range(DBH_SWEEP_LOW_CM, DBH_SWEEP_HIGH_CM + 1, DBH_SWEEP_STEP_CM)]
    phloem_only = {"bark_phloem": SWEEP_BARKS["bark_phloem"]}
    rows = _sweep_rows(dbhs, widths, GEOMETRY["standoff_m"]["values"], bark_axis, barks=phloem_only, pols=("TM",))
    key = lambda r: (r["w_cm"], r["bark"], r["polarization"], r["dbh_m"], r["standoff_mm"], r["bark_mm"])  # noqa: E731
    ref = {key(r): r for r in dbh_rows if r["polarization"] == "TM" and r["bark"] == "bark_phloem"}
    matched, worst = 0, 0.0
    for r in rows:
        c = ref.get(key(r))
        if c is None:
            continue
        matched += 1
        miss = max(abs(r[k] - c[k]) for k in SWEEP_KEYS)
        if not miss <= 0.0:
            raise RuntimeError(f"bark-sweep control: {key(r)} misses the DBH sweep's row by {miss}")
        worst = max(worst, miss)
    if matched != len(ref):
        raise RuntimeError(f"bark-sweep control: {matched} of the DBH sweep's {len(ref)} thin-end TM phloem rows revisited")
    thick = {b: SWEEP_BARKS[b] for b in ("bark_dry", "bark_wet")}
    thick_rows = _sweep_rows(dbhs, widths, GEOMETRY["standoff_m"]["values"], lambda d: bark_by_dbh(d, "thick"), barks=thick, pols=("TM",))
    rule = _rule(rows)
    floor = dict(rule["min_crossing_at"][0], crossing_3dB_deg=rule["min_crossing_deg"])
    # the deck as a 1-D family: the flange-thickness placeholder (00_07 HW.8.10) and `52`'s rows both move it — ±2 mm
    deck = []
    for off in (-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0):
        r = _resolve(floor, standoff_mm=round(floor["standoff_mm"] + off, 3), tag="deck")
        deck.append([off, round(floor["standoff_mm"] + off, 3), r["within_3dB_of_front_to_deg"], r["crossing_3dB_deg"], _loss_at_rule(r)])
    # past the thick end at the floor stem: the floor sits on the table's EDGE, not at an extremum, if the crossing keeps
    # falling beyond it (canon's own Wilms SD ±4 mm, 01_04 §3.2) — an assumption probe, carried as one
    beyond_thick = []
    for k in range(1, 9):
        r = _resolve(floor, bark_mm=round(floor["bark_mm"] + k, 3), tag="beyond_thick")
        beyond_thick.append([round(floor["bark_mm"] + k, 3), r["within_3dB_of_front_to_deg"], r["crossing_3dB_deg"], _loss_at_rule(r)])
    thick_end_is_edge = any(b[2] < rule["min_crossing_deg"] for b in beyond_thick)
    # the stem × bark floor: for each stem the bark at which the crossing is lowest, and that crossing
    floor_by_dbh = []
    for d in dbhs:
        sel = [r for r in rows if r["dbh_m"] == d]
        lo = min(sel, key=lambda r: r["crossing_3dB_deg"])
        floor_by_dbh.append([round(d * 100, 2), lo["bark_mm"], lo["w_cm"], lo["standoff_mm"], lo["within_3dB_of_front_to_deg"], lo["crossing_3dB_deg"]])
    return {
        "what": "the dead bark as an AXIS on the TM «phloem» stem — every stem of the DBH axis × every width × both decks × the "
                "bark from canon's thin to thick end in 1 mm steps, both ends derived per stem (docstring BARK SWEEP); the dry "
                "and wet proxies at the thick end only; rows skip the N + 15 truncation re-solve and keep the energy balance",
        "polarization": "TM", "bark_reading": "bark_phloem", "step_mm": BARK_AXIS_STEP_M * 1e3,
        "bark_mm_by_dbh_cm": {str(round(d * 100, 2)): [round(bark_by_dbh(d, "thin") * 1e3, 3), round(bark_by_dbh(d, "thick") * 1e3, 3)] for d in dbhs},
        "thick_end_named_stems_mm": {str(round(d * 100, 2)): round(v * 1e3, 3) for d, v in sorted(BARK_THICK_T_M.items())},
        "n_rows": len(rows), "n_bark_values": sum(len(bark_axis(d)) for d in dbhs),
        "extremes": _ext(rows),
        "by_dbh": _per_dbh(rows, ("within_3dB_of_front_to_deg", "crossing_3dB_deg", "front_minus_back_dB", "front_minus_side_dB")),
        "floor_by_dbh": {"columns": ["dbh_cm", "bark_mm", "w_cm", "standoff_mm", "sector_deg", "crossing_deg"], "rows": floor_by_dbh},
        "rule": rule,
        "rule_floor_under_a36_readings": _a36_floor_span(rule["min_crossing_at"]),
        "loss_at_rule_under_a36_readings": _a36_floor_span(rule["min_crossing_at"], key="loss_at_rule_deg_dB"),
        "tm_back_floor_under_a36_readings": _a36_floor_span(_ext(rows)["front_minus_back_dB"]["min_at"], key="front_minus_back_dB"),
        "rule_floor_refinement": _refine_floor(floor, bark_half_mm=0.5, bark_bounds_of=lambda d: (bark_by_dbh(d, "thin") * 1e3, bark_by_dbh(d, "thick") * 1e3)),
        "canon_bark_table": {"what": "01_04 §3.2 as lib.constants carries it — single bark on the plate ridges at 1.3 m per named stem, and the live "
                                     "phloem taken off each end to reach the dead bark the sweeps use (the thick-end subtraction is OUR reading)",
                             "single_bark_ridge_mm_by_dbh_cm": {str(float(cm)): list(s) for cm, s in sorted(BARK_SINGLE_RIDGE_MM_BY_DBH_CM.items())},
                             "live_phloem_mm": {"thin_end": LIVE_PHLOEM_MM_THIN_END, "thick_end_reading": LIVE_PHLOEM_MM_THICK_END_READING,
                                                "thick_end_is_our_reading_not_canon": True},
                             "dead_bark_ridge_dbh38_mm": list(BARK_DEAD_RIDGE_DBH38_MM)},
        "deck_sensitivity_at_floor_row": {"what": "the floor row re-solved with the deck moved — the flange thickness is a "
                                                  "placeholder (00_07 HW.8.10) and `52`'s rows move the deck too; offsets in mm",
                                          "columns": ["offset_mm", "standoff_mm", "sector_deg", "crossing_deg", "loss_at_rule_deg_dB"],
                                          "rows": deck,
                                          "rule_holds_from_offset_mm": next((d[0] for d in deck if d[3] >= RULE_SECTOR_DEG and d[0] > 0), None),
                                          "crossing_deg_per_mm_about_the_floor_row": round((next(d[3] for d in deck if d[0] == 1.0) - next(d[3] for d in deck if d[0] == -1.0)) / 2, 3),
                                          "loss_dB_per_mm_about_the_floor_row": round((next(d[4] for d in deck if d[0] == -1.0) - next(d[4] for d in deck if d[0] == 1.0)) / 2, 4)},
        "beyond_thick_end_at_floor_stem": {"what": "the floor row's bark thickened past canon's thick end in 1 mm steps (an "
                                                   "assumption probe — canon's ridge SD is ±4 mm, 01_04 §3.2)",
                                           "columns": ["bark_mm", "sector_deg", "crossing_deg", "loss_at_rule_deg_dB"], "rows": beyond_thick,
                                           "thick_end_is_an_edge_not_an_extremum": thick_end_is_edge,
                                           "min_crossing_deg": min(b[2] for b in beyond_thick),
                                           "min_crossing_at_bark_mm": min(beyond_thick, key=lambda b: b[2])[0]},
        "thick_end_dry_wet": {b: {"min_sector_deg": min(r["within_3dB_of_front_to_deg"] for r in thick_rows if r["bark"] == b),
                                  "min_crossing_deg": min(r["crossing_3dB_deg"] for r in thick_rows if r["bark"] == b),
                                  "n_rows": sum(1 for r in thick_rows if r["bark"] == b)} for b in thick},
        "controls": {"thin_end_rows_reproduce_the_dbh_sweep_max_abs_miss": worst, "thin_end_rows_revisited": matched},
    }


def main() -> int:
    banner("107 — the stem's own radio shadow at 868 MHz (00_07 HW.6)")
    flange_t = json.loads((CEM_DIR / "cathode_flange.json").read_text(encoding="utf-8"))["flange_thickness_mm"]
    rf_rows = [r["rf_deck_top_over_flange_mm"] for r in json.loads(Z_STACK.read_text(encoding="utf-8"))
               ["vertical_stack_budget"]["rows"] if r["fr4_is_bom"]]
    GEOMETRY.update({
        "dbh_m": {"values": [cm / 100.0 for cm in sorted(BARK_SINGLE_RIDGE_MM_BY_DBH_CM)],   # the table's named stems
                  "referent": "the stem's diameter at breast height: the smallest host (lib DBH_MIN_CM — the CODIT rule, "
                              "01_01 §1) and the two larger stems 01_04 §3.2's bark table reads",
                  "source": "lib.constants DBH_MIN_CM; 01_04 §3.2"},
        "standoff_m": {"values": [round((min(rf_rows) + flange_t) / 1000.0, 6), round((max(rf_rows) + flange_t) / 1000.0, 6)],
                       "referent": "the RF deck (the booster's radiating ground) over the bark line, which is the flange's "
                                   "UNDERSIDE (02_02): `52`'s rows of the RF-deck top over the flange's top face plus the "
                                   "flange's thickness; the low end is the named-alternative B2B 6 row, the high end B2B 10",
                       "source": f"tools/in_silico/cache/mechanical/z_stack_tolerance.json vertical_stack_budget rows "
                                 f"(FR4 of the BOM): {sorted(rf_rows)} mm; tools/cad/cem/cathode_flange.json "
                                 f"flange_thickness_mm = {flange_t} (a placeholder, 00_07 HW.8.10)"},
    })
    if not PERMITTIVITY:
        raise SystemExit("PERMITTIVITY is empty — fill it from its sources first")
    controls = controls_free_and_lossless()
    cases = []
    for name in PERMITTIVITY:
        for pol in POLARIZATIONS:
            for dbh in GEOMETRY["dbh_m"]["values"]:
                for so in GEOMETRY["standoff_m"]["values"]:
                    cases.append(run_case(dbh, so, name, pol))
    findings = {}
    for pol in POLARIZATIONS:
        rows = [r for r in cases if r["polarization"] == pol]
        findings[pol] = {
            "front_minus_back_dB": _span([r["front_minus_back_dB"] for r in rows]),
            "front_minus_side_dB": _span([r["front_minus_side_dB"] for r in rows]),
            "deepest_below_front_dB": _span([r["gain_dB"]["0"] - r["gain_dB_min"] for r in rows]),
            "deepest_at_deg": [min(r["phi_min_deg"] for r in rows), max(r["phi_min_deg"] for r in rows)],
            "within_3dB_of_front_to_deg": [min(r["within_3dB_of_front_to_deg"] for r in rows),
                                           max(r["within_3dB_of_front_to_deg"] for r in rows)],
            "front_field_same_current_dB": _span([r["field_same_current_dB"]["0"] for r in rows]),
            "efficiency_2d": _span([r["efficiency"] for r in rows], 2),
            "by_reading_front_minus_back_dB": {
                n: _span([r["front_minus_back_dB"] for r in rows if r["permittivity"] == n]) for n in PERMITTIVITY},
            "by_standoff_efficiency_2d": {
                str(round(s * 1e3, 3)): _span([r["efficiency"] for r in rows if r["standoff_mm"] == round(s * 1e3, 3)], 2)
                for s in GEOMETRY["standoff_m"]["values"]},
            # the reading(s) at each end of a span — which reading is ADVERSE is the consumer's end, read here, not typed
            "ends_by_reading": {
                k: [sorted({r["permittivity"] for r in rows if r[k] == min(x[k] for x in rows)}),
                    sorted({r["permittivity"] for r in rows if r[k] == max(x[k] for x in rows)})]
                for k in ("front_minus_back_dB", "front_minus_side_dB", "within_3dB_of_front_to_deg", "efficiency")},
        }
    # control — the A.36 bark reading's own interpolation (a CONTROL, not a named reading): every *_bark_phloem row
    # re-run at each alternative, the other rows kept; what each alternative does to the floors the findings print
    phloem = [n for n in PERMITTIVITY if n.endswith("_bark_phloem")]

    def _floors(rows):
        out = {}
        for pol in POLARIZATIONS:
            fb = [r["front_minus_back_dB"] for r in rows if r["polarization"] == pol]
            w3 = [r["within_3dB_of_front_to_deg"] for r in rows if r["polarization"] == pol]
            out[pol] = {"front_minus_back_dB_floor": _span(fb)[0], "front_minus_back_dB_floor_raw": round(min(fb), 3),
                        "within_3dB_of_front_to_deg": [min(w3), max(w3)]}
        return out

    reading_floors = _floors(cases)
    phloem_control = {"what": "every *_bark_phloem row re-run with the bark at each alternative reading of A.36, the "
                              "other rows kept — a control on the figure's interpolation, not a named reading",
                      "reading": {"eps": [BARK_PHLOEM.real, -BARK_PHLOEM.imag], **reading_floors}}
    for alt, eps in BARK_PHLOEM_CONTROLS.items():
        alt_cases = [run_case(dbh, so, n, pol, {"layers": [(PERMITTIVITY[n]["layers"][0][0], eps),
                                                           *PERMITTIVITY[n]["layers"][1:]]})
                     for n in phloem for pol in POLARIZATIONS
                     for dbh in GEOMETRY["dbh_m"]["values"] for so in GEOMETRY["standoff_m"]["values"]]
        alt_floors = _floors([r for r in cases if r["permittivity"] not in phloem] + alt_cases)
        for pol in POLARIZATIONS:
            alt_floors[pol]["floor_moves_raw_dB"] = round(alt_floors[pol]["front_minus_back_dB_floor_raw"]
                                                          - reading_floors[pol]["front_minus_back_dB_floor_raw"], 3)
        # per reading, so a sentence written on a SUBSET of the readings (the ratified text's thirteen) can be recomposed
        alt_floors["phloem_floor_raw_by_reading"] = {
            pol: {n: min(r["front_minus_back_dB"] for r in alt_cases if r["polarization"] == pol and r["permittivity"] == n)
                  for n in phloem} for pol in POLARIZATIONS}
        phloem_control[alt] = {"eps": [eps.real, -eps.imag], **alt_floors}
    # The span of the floors over the four single-reading interpolations: the printed floors hold at the MEAN of the
    # two readings, and a one-sided «at least» quoted without this span would overstate it (in-silico #43).
    singles = [k for k in BARK_PHLOEM_CONTROLS if k.startswith("single_reading_")]
    phloem_control["floor_span_over_single_readings"] = {
        pol: [min(phloem_control[k][pol]["front_minus_back_dB_floor"] for k in singles),
              max(phloem_control[k][pol]["front_minus_back_dB_floor"] for k in singles)] for pol in POLARIZATIONS}
    controls["phloem_reading"] = phloem_control
    sweep, sweep_rows_named = width_sweep(cases)
    sx = sweep["extremes"]
    dbh, dbh_rows, _beyond_rows = dbh_sweep(sweep_rows_named)
    bark = bark_sweep(dbh_rows)
    dr, bk = dbh["rule"], bark["rule"]
    dx = dbh["extremes"]
    bfail = dbh["beyond_bark_table"]["first_stem_cm_failing_by_assumption"]
    beyond_phrase = "; ".join(f"{k.replace('_', ' ')}: " + ("holds to 90 cm" if v is None else f"first fails at {v:g} cm")
                              for k, v in bfail.items())
    bk_at = bk["min_crossing_at"][0]
    tm, te = findings["TM"], findings["TE"]
    verdict = (
        f"In the horizontal plane, with the gateway straight behind the stem the field of a short dipole along the stem "
        f"(TM) is {tm['front_minus_back_dB'][0]:.1f}–{tm['front_minus_back_dB'][1]:.1f} dB below its level with the "
        f"gateway in front, and its deepest null lies {tm['deepest_below_front_dB'][0]:.1f}–"
        f"{tm['deepest_below_front_dB'][1]:.1f} dB below the front at {tm['deepest_at_deg'][0]}–{tm['deepest_at_deg'][1]}° "
        f"from it; at 90° it is {tm['front_minus_side_dB'][0]:.1f}–{tm['front_minus_side_dB'][1]:.1f} dB down, and "
        f"it stays within 3 dB of the front only to {tm['within_3dB_of_front_to_deg'][0]}–"
        f"{tm['within_3dB_of_front_to_deg'][1]}°. A dipole tangential to the bark (TE, horizontal E): "
        f"{te['front_minus_back_dB'][0]:.1f}–{te['front_minus_back_dB'][1]:.1f} dB behind, "
        f"{te['front_minus_side_dB'][0]:.1f}–{te['front_minus_side_dB'][1]:.1f} dB at 90°. Ranges span every NAMED "
        f"reading of the stem's permittivity, diameter and the antenna's standoff in this cache; over the sapwood "
        f"width's measured axis ({sweep['axis_cm'][0]}–{sweep['axis_cm'][1]} cm, the width sweep — the output is "
        f"resonant in the width) the TM 3-dB sector runs {sx['TM']['within_3dB_of_front_to_deg']['min']}–"
        f"{sx['TM']['within_3dB_of_front_to_deg']['max']}°, the TM loss at 90° reaches "
        f"{_span([sx['TM']['front_minus_side_dB']['max']])[1]:.1f} dB, and the back spans "
        f"{_span([sx['TM']['front_minus_back_dB']['min']])[0]:.1f}–{_span([sx['TM']['front_minus_back_dB']['max']])[1]:.1f} "
        f"dB (TM) and {_span([sx['TE']['front_minus_back_dB']['min']])[0]:.1f}–"
        f"{_span([sx['TE']['front_minus_back_dB']['max']])[1]:.1f} dB (TE). Over the stem's diameter as an axis too "
        f"({dbh['axis_cm'][0]}–{dbh['axis_cm'][1]} cm in {dbh['step_cm']} cm steps, the bark derived per stem, every "
        f"width, bark and standoff) the TM 3-dB sector's floor is {dr['min_sector_deg']}° on the 1° grid (the −3 dB "
        f"crossing ≥ {dr['min_crossing_deg']:.2f}°), so the ratified ±{dr['sector_deg']}° rule "
        f"{'holds' if dr['holds_on_1deg_grid'] else 'FAILS'} on that grid with a margin of {dr['margin_deg_fine']:.2f}° "
        f"on the crossing; the TM floor behind on that grid is {_span([dx['TM']['front_minus_back_dB']['min']])[0]:.1f} dB. "
        f"The dead bark is the third resonant axis: swept from canon's thin to thick end ({bark['step_mm']:g} mm steps) on the TM "
        f"«phloem» stem the sector's floor is {bk['min_sector_deg']}° (crossing ≥ {bk['min_crossing_deg']:.2f}°, at DBH "
        f"{bk_at['dbh_m'] * 100:g} cm, bark {bk_at['bark_mm']:g} mm, sapwood {bk_at['w_cm']:g} cm), so the ±{bk['sector_deg']}° rule "
        f"{'holds' if bk['holds_on_1deg_grid'] else 'FAILS'} on the 1° grid over the bark axis "
        f"({'margin ' + format(bk['margin_deg_fine'], '.2f') + '°' if bk['holds_on_1deg_grid'] else 'first failing stem ' + format(bk['first_stem_cm_failing_on_1deg_grid'] or 0, 'g') + ' cm'}); "
        f"under the dry and wet proxies the floor is {min(min(v[1] for v in dbh['tm_sector_floor_by_bark']['TM'][b]) for b in ('bark_dry', 'bark_wet'))}° "
        f"at the thin end and {min(v['min_sector_deg'] for v in bark['thick_end_dry_wet'].values())}° at the thick end; the loss at ±{bk['sector_deg']}° on the "
        f"crossing-floor row is {max(bk['loss_at_rule_deg_dB']['at_crossing_floor']):.3f} dB "
        f"({bark['loss_at_rule_under_a36_readings']['span_over_single_readings'][0]:.3f}–{bark['loss_at_rule_under_a36_readings']['span_over_single_readings'][1]:.3f} over the A.36 readings), "
        f"a deck {bark['deck_sensitivity_at_floor_row']['rule_holds_from_offset_mm']} mm higher returns the rule, and past the thick end the crossing "
        f"{'keeps falling' if bark['beyond_thick_end_at_floor_stem']['thick_end_is_an_edge_not_an_extremum'] else 'rises'} (the floor is an edge of the table). "
        f"Past the bark table (stems to {dbh['beyond_bark_table']['axis_cm'][1]} cm, three bark assumptions) the rule — "
        f"{beyond_phrase}. "
        f"The 2-D efficiency indicator — "
        f"what the near field loses into the stem — is {tm['efficiency_2d'][0]:.2f}–{tm['efficiency_2d'][1]:.2f} (TM) "
        f"and {te['efficiency_2d'][0]:.2f}–{te['efficiency_2d'][1]:.2f} (TE); it is not the 3-D antenna efficiency.")
    result = {
        "script": Path(__file__).name,
        "frequency_Hz": F_HZ,
        "wavelength_m": round(C0 / F_HZ, 6),
        "convention": "e^{jωt}; ε_r = ε′ − jε″; φ = 0 is the bearing from the stem's axis through the node",
        "outputs": {
            "field_same_current_dB": "|F(φ)|² — the far field with the tree against the same source current without "
                                     "it; EXACT in the horizontal plane for a short dipole (TM) or small loop (TE) "
                                     "along an infinite stem (k_z = 0)",
            "gain_dB": "|F(φ)|²/(P_in/P₀) — the same field at equal INPUT power; 2-D normalisation, an indicator",
            "efficiency": "P_rad/P_in in 2-D — an indicator of the near-field loss, not the 3-D antenna efficiency",
        },
        "readings": {"permittivity": {n: {"layers_bark_inward": [[t, e.real, -e.imag] for t, e in r["layers"]],
                                          **{k: r[k] for k in ("sapwood_width_m", "width_read_at_height_m") if k in r},
                                          "source": r["source"]} for n, r in PERMITTIVITY.items()},
                     "geometry": {k: {"values": v["values"], "referent": v["referent"], "source": v["source"]}
                                  for k, v in GEOMETRY.items()},
                     "polarization": {"TM": "an electric line current along the stem — E along the stem",
                                      "TE": "a magnetic line current along the stem — E horizontal"}},
        "tolerances": {"free_space": TOL_FREE, "lossless": TOL_LOSSLESS, "balance": TOL_BALANCE,
                       "truncation": TOL_TRUNC},
        "controls": controls,
        "cases": cases,
        "findings": findings,
        "width_sweep": sweep,
        "dbh_sweep": dbh,
        "bark_sweep": bark,
        "verdict": verdict,
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\n  {'pol':3s} {'reading':28s} {'DBH':>5s} {'so mm':>6s} {'F0 dB':>6s} {'G0':>6s} {'G90':>6s} "
          f"{'G180':>6s} {'min@':>9s} {'eff':>5s}")
    for r in cases:
        g = r["gain_dB"]
        print(f"  {r['polarization']:3s} {r['permittivity']:28s} {r['dbh_m']:5.2f} {r['standoff_mm']:6.1f} "
              f"{r['field_same_current_dB']['0']:6.1f} {g['0']:6.1f} {g['90']:6.1f} {g['180']:6.1f} "
              f"{r['gain_dB_min']:6.1f}@{r['phi_min_deg']:<6.1f} {r['efficiency']:5.2f}")
    print("\n  " + verdict)
    for alt in BARK_PHLOEM_CONTROLS:
        c = phloem_control[alt]
        print(f"  control A.36 {alt} ({c['eps'][0]} − j{c['eps'][1]}): floors TM {c['TM']['front_minus_back_dB_floor']}"
              f" (raw {c['TM']['floor_moves_raw_dB']:+.3f} dB) · TE {c['TE']['front_minus_back_dB_floor']}"
              f" (raw {c['TE']['floor_moves_raw_dB']:+.3f} dB)")
    print(f"  width sweep {sweep['axis_cm'][0]}–{sweep['axis_cm'][1]} cm, {sweep['n_widths']} widths, {sweep['n_rows']} rows "
          f"(named widths reproduce the readings: max miss {sweep['controls']['named_widths_reproduce_the_readings_max_abs_miss']})")
    for pol in POLARIZATIONS:
        for k in SWEEP_KEYS:
            e = sweep["extremes"][pol][k]
            print(f"    {pol} {k:28s} min {e['min']} at {[a['w_cm'] for a in e['min_at']]} · max {e['max']} at "
                  f"{[a['w_cm'] for a in e['max_at']]}")
    print(f"  DBH sweep {dbh['axis_cm'][0]}–{dbh['axis_cm'][1]} cm, {dbh['n_stems']} stems, {dbh['n_rows']} rows "
          f"(named stems reproduce the width sweep: {dbh['controls']['named_stems_rows_revisited']} rows, max miss "
          f"{dbh['controls']['named_stems_reproduce_the_width_sweep_max_abs_miss']}; standoff monotone violations "
          f"{dbh['controls']['standoff_monotone_crossing_violations']})")
    print(f"    rule ±{dr['sector_deg']}°: {'holds' if dr['holds_on_1deg_grid'] else 'FAILS'} on the 1° grid — sector floor "
          f"{dr['min_sector_deg']}° at {[(a['dbh_m'], a['w_cm'], a['bark'], a['standoff_mm']) for a in dr['min_sector_at']][:6]}, "
          f"crossing floor {dr['min_crossing_deg']} (margin {dr['margin_deg_fine']}°)")
    for pol in POLARIZATIONS:
        for k in ("front_minus_back_dB", "front_minus_side_dB", "within_3dB_of_front_to_deg", "crossing_3dB_deg"):
            e = dx[pol][k]
            print(f"    {pol} {k:28s} min {e['min']} at {[(a['dbh_m'], a['w_cm']) for a in e['min_at']][:4]} · max {e['max']}")
    print(f"    beyond the table ({dbh['beyond_bark_table']['rule']['sector_deg']}° rule) — {beyond_phrase}")
    print(f"  bark sweep: {bark['n_rows']} rows over {bark['n_bark_values']} (stem, bark) values; thin-end rows reproduce the DBH "
          f"sweep: {bark['controls']['thin_end_rows_revisited']} rows, max miss {bark['controls']['thin_end_rows_reproduce_the_dbh_sweep_max_abs_miss']}")
    print(f"    rule ±{bk['sector_deg']}° over the bark axis: {'holds' if bk['holds_on_1deg_grid'] else 'FAILS'} — sector floor "
          f"{bk['min_sector_deg']}° / crossing floor {bk['min_crossing_deg']} at {[(a['dbh_m'], a['bark_mm'], a['w_cm'], a['standoff_mm']) for a in bk['min_crossing_at']][:4]}; "
          f"first failing stem {bk['first_stem_cm_failing_on_1deg_grid']}; A.36 span {bark['rule_floor_under_a36_readings']['span_over_single_readings']}; "
          f"dry/wet thick end {bark['thick_end_dry_wet']}")
    print(f"    standoff monotonicity by polarization: {dbh['controls']['standoff_monotone_by_polarization']}")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
