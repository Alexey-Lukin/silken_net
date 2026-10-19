#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Стаття 1 publication figures — built entirely from the cached DFT results.

This script *reads the JSON caches only* (no PySCF, no DFT) and renders the
data-driven paper figures into `docs/protocols/ebfc/in_silico/paper/figures/`:

  * fig3_cascade_lfer.png   — (a) FADH₂→Os Marcus/MO cascade + PCET anchor (④)
                              (b) mediator Hammett LFER design rule (①)
  * fig4_cathode_det.png    — (a) ZIF Cu-Co-Ce coupling ladder; (b) k_DET margin
                              vs reorganization-energy scenario (③, conditional on λ(Co))
  * fig5_cascade_like_for_like.png — (a) the cascade like for like per Os form and donor level (95);
                              (b) its gap split into the donor and acceptor sides (cancellations named)
  * figS1_betad_ensemble.png — WITHDRAWN 2026-10-15 (cluster 6): no longer generated, `figS1()` kept as the record

Every headline number is cross-checked against the SUMMARY.md canon with an
assert — if a cache drifts (someone re-runs a DFT script), the figure build
fails loudly instead of silently shipping a wrong plot.

Run
---
    mamba run -n silken_md python tools/in_silico/scripts/60_paper_figures.py
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
from lib.constants import DFT_CACHE, PAPER_FIG_DIR, REPO_ROOT

# ── house style (publication-grade, glyph-safe) ──
plt.rcParams.update(
    {
        "savefig.dpi": 300,
        "figure.dpi": 120,
        "font.family": "DejaVu Sans",  # carries ₂ ₃ Δ σ λ → × ⁻ ° glyphs
        "font.size": 9,
        "axes.titlesize": 10,
        "axes.labelsize": 9,
        "legend.fontsize": 7.5,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.alpha": 0.25,
    }
)

SI_DESCRIPTION = "Publication figures, rendered entirely from the cached DFT results."  # its row in the paper SI (72): English, no repo jargon

# Okabe-Ito colour-blind-safe palette
C = {
    "blue": "#0072B2",
    "red": "#D55E00",
    "green": "#009E73",
    "orange": "#E69F00",
    "purple": "#CC79A7",
    "sky": "#56B4E9",
    "grey": "#999999",
    "yellow": "#F0E442",
}


def _load(name: str) -> dict:
    p = DFT_CACHE / name
    if not p.exists():
        sys.exit(f"Missing cache: {p} — run the upstream DFT script first.")
    return json.loads(p.read_text(encoding="utf-8"))


def _close(a: float, b: float, tol: float, what: str) -> None:
    if abs(a - b) > tol:
        sys.exit(f"CANON DRIFT [{what}]: cache {a:.4f} vs SUMMARY {b:.4f} (tol {tol})")


# ─────────────────────────────────────────────────────────────────────────────
# Fig 3 — (a) cascade + PCET anchor (④) · (b) mediator LFER (①)
# ─────────────────────────────────────────────────────────────────────────────
def fig3() -> None:
    osc = _load("os_complex.json")
    pcet = _load("pcet_redox_potential.json")
    series = _load("os_mediator_series.json")
    flav = _load("lumiflavin.json")

    fadh2_homo = flav["red"]["HOMO_eV"]  # cache-sourced (drift-proof), not a hardcoded mirror
    os3_lumo = osc["os3_plus"]["LUMO_eV"]
    raw_delta = fadh2_homo - os3_lumo
    _close(fadh2_homo, -4.018, 0.01, "FADH₂ HOMO")
    _close(os3_lumo, -4.086, 0.01, "Os(III) LUMO (dimethyl)")
    _close(raw_delta, 0.068, 0.01, "raw Δε (dimethyl)")
    e_pcet_ph7 = pcet["E_vs_SHE_mV"]["pH_7.0"]
    _close(e_pcet_ph7, -155.4, 1.0, "PCET E° pH7")
    (d_exp,) = pcet["delta_vs_exp_pH7_mV"]  # vs −220 mV (ref 25), the only reading carried — 00_07 HW.5.IS
    _close(d_exp, 64.6, 1.0, "PCET Δ vs exp −220")
    e_zpe = _load("pcet_redox_potential_thermo.json")["E_vs_SHE_mV"]["relaxed_plus_zpe"]["pH_7.0"]
    _close(e_zpe, -429.5, 1.0, "PCET E° pH7, relaxed + ZPE (32b)")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(9.6, 4.3))

    # ---- (a) MO / Marcus cascade ladder ----
    bw = 0.30
    for x, e, col in [(0, fadh2_homo, C["blue"]), (1, os3_lumo, C["red"])]:
        axa.hlines(e, x - bw, x + bw, colors=col, linewidth=3.4, zorder=3)
        axa.text(x, e + 0.05, f"{e:.3f} eV", ha="center", va="bottom", fontsize=8, color=col)
    axa.text(0, fadh2_homo - 0.07, "FADH₂\n(donor HOMO)", ha="center", va="top", fontsize=7.8)
    axa.text(1, os3_lumo - 0.07, "Os(III)\n(acceptor LUMO)", ha="center", va="top", fontsize=7.8)
    # no electron-transfer arrow: a one-electron orbital offset carries no direction for the 2e⁻/2H⁺ step
    # (⚖️ founder 2026-10-19, D — no conclusion from the sign of a one-electron reading)
    lo, hi = min(fadh2_homo, os3_lumo), max(fadh2_homo, os3_lumo)   # limits follow the levels, never typed
    axa.text(0.5, hi + 0.17, f"Koopmans offset Δε = {raw_delta:+.3f} eV (programmatic Os geometry;\n≈ 0 on Os(III)'s own minimum)", ha="center",
             va="bottom", fontsize=7.3, color=C["purple"])

    axa.text(0.02, 0.97,
             "Exp-anchored: +574 mV (−0.574 eV) downhill\n"
             "[E°(Os)+309 − E°(FAD-GDH)−265 mV vs SHE]\n"
             f"raw Δε {raw_delta:+.2f} eV (B3LYP Koopmans, one-electron — not like-for-like with it; → §3.5)",
             transform=axa.transAxes, fontsize=6.4, va="top", ha="left",
             bbox={"boxstyle": "round,pad=0.35", "fc": "#eef6ff", "ec": C["blue"], "alpha": 0.92})
    axa.text(0.98, 0.03,
             f"PCET E°(FAD/FADH₂), pH 7: {e_pcet_ph7:.0f} mV (MMFF geometries, electronic)\n"
             f"{e_zpe:.0f} mV relaxed + ZPE (32b); exp −220 — neither is a validation (§3.2)".replace("-", "−"),
             transform=axa.transAxes, fontsize=6.4, va="bottom", ha="right",
             bbox={"boxstyle": "round,pad=0.35", "fc": "#eefaf2", "ec": C["green"], "alpha": 0.92})
    axa.set_xlim(-0.55, 1.55)
    axa.set_ylim(lo - 0.55, hi + 0.6)
    axa.set_xticks([])
    axa.set_ylabel("Orbital energy (eV)")
    axa.set_title("(a) Frontier-orbital levels (one-electron)")
    axa.grid(True, axis="y", alpha=0.25)

    # ---- (b) Hammett LFER ----
    cx = series["complexes"]
    lbl = {"nme2": "NMe₂", "nh2": "NH₂", "ome": "OMe", "dmbpy": "Me", "bpy": "H",
           "cl": "Cl", "dcbpy": "COOH", "no2": "NO₂", "cf3": "CF₃", "so2cf3": "SO₂CF₃"}
    sig = np.array([c["sigma_para"] for c in cx])
    dered = np.array([c["dE_red_eV"] for c in cx])
    casc = np.array([c["cascade_delta_eV"] for c in cx])
    names = [c["name"] for c in cx]
    _close(casc[names.index("bpy")], 0.2097, 0.005, "① cascade(H)")
    _close(casc[names.index("so2cf3")], 0.8921, 0.005, "① cascade(SO₂CF₃)")
    _close(casc[names.index("nme2")], -0.3823, 0.005, "① cascade(NMe₂)")

    # Hammett LFER (classic monosubstituents OMe→NO₂, the linear regime): slope/intercept/r²
    # are COMPUTED in 21e over REF_LFER_SET and read from os_mediator_series.json — single
    # source, so fig/table/prose cannot drift. Excluded (overlaid as called-out points):
    # NMe₂/NH₂ (σ⁻ donor saturation) + inert CF₃-family design picks (high-σ flattening).
    lf = series["lfer"]
    ref = lf["fit_set"]
    ri = [names.index(n) for n in ref]
    slope, intercept, r2 = lf["slope_eV_per_sigma"], lf["intercept_eV"], lf["r2"]
    _close(slope, -0.92, 0.01, "① LFER slope (OMe→NO₂)")
    xs = np.linspace(sig[ri].min() - 0.05, 1.0, 50)
    axb.plot(xs, slope * xs + intercept, color=C["grey"], lw=1.2, ls="--", zorder=1,
             label=f"ΔE_red LFER  {slope:.2f} eV/σ (r²={r2:.2f})")

    axb.scatter(sig, dered, s=42, color=C["blue"], zorder=3, label="ΔE_red(III→II)")
    axb.scatter(sig, casc, s=42, marker="s", color=C["red"], zorder=3, label="Koopmans offset Δε")
    # mark unstable NO₂ with an open ring
    i_no2 = names.index("no2")
    axb.scatter(sig[i_no2], casc[i_no2], s=140, facecolors="none", edgecolors="k", lw=1.1, zorder=4)
    axb.scatter(sig[i_no2], dered[i_no2], s=140, facecolors="none", edgecolors="k", lw=1.1, zorder=4)

    ann = {
        "nme2": ("donor saturation", (2, 8)),
        "bpy": ("H (ref)", (5, -11)),
        "cf3": ("CF₃ inert", (6, -14)),
        "so2cf3": ("SO₂CF₃ inert", (4, -13)),   # just under its own square; not «optimum» — its order vs NO₂ is open (⚖️ 2026-10-15)
        "no2": ("NO₂ unstable", (-4, 9)),
    }
    for n, (txt, off) in ann.items():
        i = names.index(n)
        axb.annotate(txt, (sig[i], casc[i]), textcoords="offset points",
                     xytext=off, fontsize=6.6, color="k", ha="right" if off[0] < 0 else "left")
    # plain substituent labels on ΔE_red points
    lbl_off = {"cf3": (4, -10)}   # CF₃ (σ 0.54) sits beside COOH (σ 0.45) — one label above, one below
    for i, n in enumerate(names):
        axb.annotate(lbl[n], (sig[i], dered[i]), textcoords="offset points", xytext=lbl_off.get(n, (3, 4)),
                     fontsize=6.3, color=C["blue"])

    axb.axvspan(-0.9, -0.55, color=C["yellow"], alpha=0.18, zorder=0)  # donor-saturation regime
    axb.set_ylim(min(dered.min(), casc.min()) - 0.4, casc.max() + 0.5)   # every point on the axes
    axb.set_xlabel("Hammett σ$_{para}$ (4,4′-bpy substituent)")
    axb.set_ylabel("Energy (eV)")
    axb.set_title("(b) Mediator structure–activity (Hammett LFER)")
    axb.legend(loc="center left", frameon=True, framealpha=0.9)

    fig.tight_layout()
    out = PAPER_FIG_DIR / "fig3_cascade_lfer.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}  (slope {slope:.3f} eV/σ)")


# ─────────────────────────────────────────────────────────────────────────────
# Fig 4 — cathode DET (③): (a) coupling ladder · (b) k_DET margin vs λ
# ─────────────────────────────────────────────────────────────────────────────
def fig4() -> None:
    ket = _load("cathode_ket_lambda.json")
    t = ket["t_ij_eV"]
    fo = ket["fodft_cuco_rigor"]
    sc = ket["scenarios"]
    # 505a1fac4 (2026-09-21) split the margin into a bracket over the gap sign, and 2026-09-24 added
    # the λ(Cu) reading as its second axis: panel (b) draws the ΔG = 0 column as the bar and the
    # bracket's two CORNERS as its whisker, so the figure says what the table and §3.4 say.
    # ⊕ 2026-10-15 (self-review cluster 8): the scenario table runs on the FO-DFT coupling, so its literature row IS the
    # FO-DFT reading, and the crude ΔSCF t is drawn as the unresolved value it is (`t_ij_crude_dscf_eV`).
    _close(sc["literature λ"]["margin_vs_turnover_at_dG0"], 25.165, 0.1, "③ lit-λ margin (ΔG=0, FO-DFT t)")
    _close(fo["margin_vs_turnover_by_dG_sign"]["dG=0"], 25.165, 0.1, "③ FO-DFT margin")
    _close(fo["t_ij_eV"], 0.005462, 1e-4, "③ FO-DFT t_ij")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(9.6, 4.3))

    # ---- (a) coupling ladder |t_ij| ----
    bars = [
        ("Cu–Co\n(crude ΔSCF,\nunresolved)", ket["t_ij_crude_dscf_eV"]["Cu-Co"], C["grey"]),
        ("Cu–Co\n(FO-DFT)", fo["t_ij_eV"], C["red"]),
        ("Co–Ce", t["Co-Ce"], C["blue"]),
        ("Ce–C", t["Ce-C"], C["green"]),
    ]
    xs = np.arange(len(bars))
    axa.bar(xs, [b[1] for b in bars], color=[b[2] for b in bars], width=0.62, zorder=3)
    for x, (_, v, _c) in zip(xs, bars, strict=False):
        axa.text(x, v * 1.12, f"{v:.4f}", ha="center", va="bottom", fontsize=7)
    axa.set_yscale("log")
    axa.set_xticks(xs)
    axa.set_xticklabels([b[0] for b in bars])
    axa.set_ylabel("electronic coupling |t$_{ij}$| (eV)")
    axa.set_title("(a) ZIF Cu–Co–Ce coupling — Cu–Co is the bottleneck")
    axa.set_ylim(5e-4, 0.4)
    axa.annotate("rate-limiting hop", xy=(0.5, fo["t_ij_eV"]), xytext=(1.4, 0.05),
                 fontsize=7, arrowprops={"arrowstyle": "->", "color": "k", "lw": 0.8})

    # ---- (b) k_DET margin vs turnover ----
    order = ["canon λ=0.7 (old assumption)", "literature λ", "computed λ (B3LYP)", "Ru-swap (Co→Ru, computed)"]
    lam_lit, lam_c = ket["lambda_lit_eV"], ket["lambda_computed_eV"]
    disp = ["canon λ=0.7\n(withdrawn)",
            f"literature λ\nλ(Co) {lam_lit['Co']:.1f}, assumed",
            f"computed λ\nλ(Co) {lam_c['Co']:.2f}", "Ru-swap\n(indicative)"]
    margins = [sc[k]["margin_vs_turnover_at_dG0"] for k in order]
    lows = [sc[k]["margin_vs_turnover_adverse"] for k in order]
    highs = [sc[k]["margin_vs_turnover_favourable"] for k in order]
    cols = [C["grey"], C["orange"], C["red"], C["green"]]
    xs = np.arange(len(order))
    axb.bar(xs, margins, color=cols, width=0.6, zorder=3)
    axb.errorbar(xs - 0.12, margins, yerr=[np.subtract(margins, lows), np.subtract(highs, margins)],
                 fmt="none", ecolor="k", capsize=3, lw=1.0, zorder=4,
                 label="bracket: adverse ↔ favourable corner\n(gap sign × λ(Cu) reading)")
    for x, m, lo in zip(xs, margins, lows, strict=False):
        axb.text(x + 0.05, lo * 0.55, f"×{lo:.2g}", ha="left", va="top", fontsize=6.5)
        axb.text(x, m * 1.4, f"×{m:.3g}", ha="center", va="bottom", fontsize=7)


    axb.axhline(1.0, color="k", lw=1.1, ls="--", zorder=2)
    axb.text(2.0, 1.25, "enzymatic turnover (10³ s⁻¹)", ha="center", va="bottom", fontsize=7)
    axb.set_yscale("log")
    axb.set_xticks(xs)
    axb.set_xticklabels(disp, fontsize=7)
    axb.set_ylabel("k$_{DET}$ margin vs turnover  (×)")
    axb.set_title("(b) DET margin (FO-DFT t) — conditional on λ(Co)")
    axb.set_ylim(3e-7, 3e7)
    axb.legend(loc="upper right", frameon=False)

    fig.tight_layout()
    out = PAPER_FIG_DIR / "fig4_cathode_det.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}")


# ─────────────────────────────────────────────────────────────────────────────
# Fig 5 — solvation / PCM limit (②): (a) explicit waters · (b) speciation + benchmark
# ─────────────────────────────────────────────────────────────────────────────
def fig5() -> None:
    """Fig 5 — the cascade like for like (`95`; ⚖️ founder 2026-10-16 «напрямок + таблиця»): (a) every Os form at the four
    donor levels against the measured cascade for the same free couples; (b) each (form, level) as its donor and acceptor
    side — the gap is their sum, so a point on the anti-diagonal band is two errors cancelling (95 names them), never a
    validation. Signs are kept: no abs() anywhere (in-silico §When Modifying #5)."""
    lfl = _load("cascade_like_for_like.json")
    levels = [("mmff_electronic", "MMFF el. (32)", "o", C["grey"]), ("relaxed_electronic", "relaxed el. (32b)", "s", C["blue"]),
              ("relaxed_plus_zpe", "+ ZPE, flavin only", "^", C["red"]), ("relaxed_rrho_free_energy", "+ RRHO, flavin only", "v", C["orange"])]
    short = {"chloro (device, programmatic)": "Cl\n(device)", "chloro + 1 H₂O on Cl⁻": "Cl\n+1 H₂O", "chloro + 2 H₂O on Cl⁻": "Cl\n+2 H₂O",
             "chloro + 3 H₂O on Cl⁻": "Cl\n+3 H₂O", "chloro, Os(II) relaxed, Os(III) vertical": "Cl, Os(II)\nrelaxed",
             "chloro, both states relaxed (adiabatic)": "Cl, both\nrelaxed", "aqua (methodological reference)": "aqua\n(ref.)",
             "bis-imidazole (operando form)": "bis-Im"}
    forms = lfl["forms"]
    meas = lfl["measured"]["cascade_same_couples_V"] * 1000
    _close(meas, 529.0, 0.5, "measured cascade, same free couples")
    _close(forms[0]["by_donor_level"]["relaxed_plus_zpe"]["cascade_V"] * 1000, 529.3, 1.0, "device form, + ZPE")
    bs = lfl["both_sided"]["levels"]
    i_bs = [f["form"] for f in forms].index(lfl["both_sided"]["form"])
    vals = [f["by_donor_level"][k]["cascade_V"] * 1000 for f in forms for k, *_ in levels]
    vals.append(bs["relaxed_plus_zpe"]["cascade_V"] * 1000)
    if min(vals) <= 0:   # panel (a)'s title is read from the points, never typed
        sys.exit(f"CANON DRIFT [Fig 5]: a like-for-like cascade is not downhill (min {min(vals):+.1f} mV) — rewrite §3.5")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(10.6, 4.5))

    # ---- (a) the cascade per form and donor level ----
    xs = np.arange(len(forms))
    offs = np.linspace(-0.27, 0.27, len(levels))
    for (k, lab, mk, col), o in zip(levels, offs, strict=True):
        axa.scatter(xs + o, [f["by_donor_level"][k]["cascade_V"] * 1000 for f in forms], marker=mk, s=28, color=col,
                    label=lab, zorder=3)
    axa.scatter([i_bs + offs[2]], [bs["relaxed_plus_zpe"]["cascade_V"] * 1000], marker="*", s=120, color=C["purple"],
                zorder=4, label="+ ZPE on both sides (96)")
    axa.axhline(meas, color="k", ls="--", lw=1.0, label=f"measured: free flavin, film-bound Os ({meas:+.0f} mV)")
    axa.axhline(0, color="k", lw=0.6)
    axa.set_xticks(xs)
    axa.set_xticklabels([short[f["form"]] for f in forms], fontsize=6.4)
    axa.set_ylabel("cascade E°(Os) − E°(FAD/FADH₂), mV   (> 0 = downhill)")
    axa.set_ylim(min(0.0, min(vals)) - 40, max(vals) + 160)
    axa.set_title(f"(a) Downhill in every form at every donor level\n(smallest {min(vals):+.0f} mV; one SHE scale, B3LYP/C-PCM)")
    axa.legend(fontsize=6.0, loc="upper left", frameon=False, ncol=2)

    # ---- (b) the gap split into its two sides ----
    gap_max = lfl["cancellations"]["gap_max_V"] * 1000
    donor = {k: lfl["flavin"]["levels"][k]["donor_side_V"] * 1000 for k, *_ in levels}
    acc = [f["acceptor_side_V"] * 1000 for f in forms]
    xs_all = [*donor.values(), bs["relaxed_plus_zpe"]["donor_side_V"] * 1000]
    ys_all = [*acc, bs["relaxed_plus_zpe"]["acceptor_side_V"] * 1000]
    lo, hi = min(xs_all + ys_all) - 60, max(xs_all + ys_all) + 60
    line = np.array([lo, hi])
    axb.fill_between(line, -line - gap_max, -line + gap_max, color=C["green"], alpha=0.18, lw=0,
                     label=f"|gap| ≤ {gap_max:.0f} mV")
    axb.plot(line, -line, color=C["green"], lw=0.9)
    for k, lab, mk, col in levels:
        axb.scatter([donor[k]] * len(forms), acc, marker=mk, s=26, color=col, label=lab, zorder=3)
    axb.scatter([bs["relaxed_plus_zpe"]["donor_side_V"] * 1000], [bs["relaxed_plus_zpe"]["acceptor_side_V"] * 1000],
                marker="*", s=120, color=C["purple"], zorder=4, label="+ ZPE on both sides (96)")
    for f, a in zip(forms, acc, strict=True):
        axb.annotate(short[f["form"]].replace("\n", " "), (max(donor.values()), a), textcoords="offset points",
                     xytext=(6, -2), fontsize=5.4, color=C["grey"])
    axb.axhline(0, color="k", lw=0.5)
    axb.axvline(0, color="k", lw=0.5)
    axb.set_xlim(lo, hi)
    axb.set_ylim(lo, hi)
    axb.set_xlabel("donor side: computed − measured flavin, mV")
    axb.set_ylabel("acceptor side: measured − computed Os, mV")
    axb.set_title("(b) The gap is the sum of the two sides —\non the band they cancel; no point is a validation")
    axb.legend(fontsize=5.8, loc="lower left", frameon=False)

    fig.tight_layout()
    out = PAPER_FIG_DIR / "fig5_cascade_like_for_like.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}")


# ─────────────────────────────────────────────────────────────────────────────
# Fig 2 — AF3 structure + the burial depth of the flavin (DRAFT: 2D PCA projection). No tunnelling route is drawn:
# script 28 is a contact-graph search from the phosphate/ribose end of FAD, not a pathway (self-review cluster 6)
# ─────────────────────────────────────────────────────────────────────────────
def fig2() -> None:
    """DRAFT structure figure from the AF3 PDB (mdtraj) — a 2D PCA projection of the
    Cα envelope with the FAD cofactor and the N5 → Tyr90 OH burial depth (no tunnelling path — §3.1). NOT a
    publication cartoon (that needs PyMOL/ChimeraX on `dgrGcGDH_AF3.pdb`); this
    conveys the §3.1 architecture (buried FAD, exit path, depth) from the real coords."""
    import mdtraj as md  # local import — only Fig 2 needs it

    from lib.constants import AF3_PDB

    t = md.load(str(AF3_PDB))
    top = t.topology
    xyz = t.xyz[0] * 10.0  # nm → Å

    ca = top.select("name CA")
    ca_xyz = xyz[ca]
    c = ca_xyz.mean(0)
    _, _, Vt = np.linalg.svd(ca_xyz - c, full_matrices=False)   # PCA frame from Cα
    Pm = Vt[:2].T

    def proj(pts):
        return (np.atleast_2d(pts) - c) @ Pm

    fad_heavy = [i for i in top.select("resname FAD") if top.atom(i).element.symbol != "H"]
    n5 = top.select("resname FAD and name N5")
    tyr_oh = top.select("resSeq 90 and name OH")
    d_fad = float(np.linalg.norm(xyz[n5[0]] - xyz[tyr_oh[0]])) if len(n5) and len(tyr_oh) else None
    if d_fad:
        _close(d_fad, 16.0, 0.5, "Fig2 d_FAD (N5→Tyr90 OH)")

    fig, ax = plt.subplots(figsize=(6.6, 5.8))
    pc = proj(ca_xyz)
    ax.scatter(pc[:, 0], pc[:, 1], s=4, color="#cfcfcf", alpha=0.5, label="protein Cα", zorder=1)
    pf = proj(xyz[fad_heavy])
    ax.scatter(pf[:, 0], pf[:, 1], s=14, color=C["orange"], label="FAD cofactor", zorder=3)
    if len(tyr_oh):
        pe = proj(xyz[tyr_oh[0]])[0]
        ax.scatter([pe[0]], [pe[1]], s=70, marker="*", color=C["green"], zorder=5, label="Tyr90 OH (surface)")
        if len(n5):
            pn = proj(xyz[n5[0]])[0]
            ax.plot([pn[0], pe[0]], [pn[1], pe[1]], ":", color="k", lw=1.0, zorder=2, label="N5 → Tyr90 OH (burial depth)")
    txt = (f"d_FAD (N5→Tyr90 OH) = {d_fad:.1f} Å  (burial depth; single-step ceiling ≈20 Å)\n"
           "no tunnelling pathway drawn — §3.1")
    ax.text(0.02, 0.02, txt, transform=ax.transAxes, fontsize=7, va="bottom",
            bbox={"boxstyle": "round,pad=0.4", "fc": "#f5f5f5", "ec": "#888888", "alpha": 0.95})
    ax.set_xlabel("PC1 (Å)")
    ax.set_ylabel("PC2 (Å)")
    ax.set_title("(DRAFT) AF3 structure + FAD burial depth\n2D PCA projection — publication cartoon → PyMOL")
    ax.legend(loc="upper right", fontsize=6.5, frameon=True, framealpha=0.9)
    ax.set_aspect("equal")
    fig.tight_layout()
    out = PAPER_FIG_DIR / "fig2_structure_path.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}  (DRAFT, d_FAD {d_fad:.1f} Å)")


# ─────────────────────────────────────────────────────────────────────────────
# Fig S1 — tunneling β·d ensemble robustness (SI)
# ─────────────────────────────────────────────────────────────────────────────
def figS1() -> None:
    te = _load("tunneling_ensemble.json")
    mean, std = te["beta_d_mean"], te["beta_d_std"]
    single = te["beta_d_single_snapshot_AF3"]
    nfr = te["n_valid_frames"]

    fig, ax = plt.subplots(figsize=(5.2, 4.0))
    ax.axhspan(mean - std, mean + std, color=C["blue"], alpha=0.15, label=f"ensemble ±σ ({mean:.2f}±{std:.2f})")
    ax.errorbar([1], [mean], yerr=[std], fmt="o", color=C["blue"], ms=9, capsize=5, lw=1.6,
                label=f"MD ensemble (n={nfr})")
    ax.scatter([0], [single], s=90, marker="D", color=C["red"], zorder=4, label=f"AF3 single snapshot ({single:.2f})")
    ax.set_xlim(-0.6, 1.6)
    ax.set_xticks([0, 1])
    ax.set_xticklabels(["static\n(AF3)", "dynamic\n(MD)"])
    ax.set_ylabel("ln Σw of the route heuristic (not a Beratan–Onuchic decay)")
    ax.set_title("The script-28 route persists over the MD ensemble\n(a connectivity heuristic — no coupling or gating derived)")
    ax.legend(loc="upper right", frameon=False, fontsize=7)
    fig.tight_layout()
    out = PAPER_FIG_DIR / "figS1_betad_ensemble.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}")


def main() -> int:
    PAPER_FIG_DIR.mkdir(parents=True, exist_ok=True)
    print("Building Стаття 1 figures from cache (no DFT) …")
    fig2()
    fig3()
    fig4()
    fig5()
    # figS1() — withdrawn 2026-10-15 (self-review round 1, cluster 6): 28 and 28b start from different atoms and
    # measure no coupling, so the figure compared nothing; the function stays as the record of what it drew.
    print("Done — all canon cross-checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
