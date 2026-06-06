#!/usr/bin/env python
"""
Стаття 1 publication figures — built entirely from the cached DFT results.

This script *reads the JSON caches only* (no PySCF, no DFT) and renders the
data-driven paper figures into `docs/protocols/ebfc/in_silico/paper/figures/`:

  * fig3_cascade_lfer.png   — (a) FADH₂→Os Marcus/MO cascade + PCET anchor (④)
                              (b) mediator Hammett LFER design rule (①)
  * fig4_cathode_det.png    — (a) ZIF Cu-Co-Ce coupling ladder; (b) k_DET margin
                              vs reorganization-energy scenario (③, honest borderline)
  * fig5_solvation_pcm.png  — (a) explicit Cl⁻-water series; (b) speciation shift
                              (B3LYP↔ωB97X) + group-8 [Os(H₂O)₆] PCM benchmark (②)
  * figS1_betad_ensemble.png — MD-ensemble vs single-snapshot tunneling β·d (SI)

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
    _close(fadh2_homo, -5.137, 0.01, "FADH₂ HOMO")
    _close(os3_lumo, -4.228, 0.01, "Os(III) LUMO")
    _close(raw_delta, -0.909, 0.01, "raw Δε")
    e_pcet_ph7 = pcet["E_vs_SHE_mV"]["pH_7.0"]
    _close(e_pcet_ph7, -158.4, 1.0, "PCET E° pH7")
    _close(pcet["delta_vs_exp_pH7_mV"], 49.6, 1.0, "PCET Δ vs exp")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(9.6, 4.3))

    # ---- (a) MO / Marcus cascade ladder ----
    bw = 0.30
    for x, e, col in [(0, fadh2_homo, C["blue"]), (1, os3_lumo, C["red"])]:
        axa.hlines(e, x - bw, x + bw, colors=col, linewidth=3.4, zorder=3)
        axa.text(x, e + 0.05, f"{e:.3f} eV", ha="center", va="bottom", fontsize=8, color=col)
    axa.text(0, fadh2_homo - 0.07, "FADH₂\n(donor HOMO)", ha="center", va="top", fontsize=7.8)
    axa.text(1, os3_lumo - 0.07, "Os(III)\n(acceptor LUMO)", ha="center", va="top", fontsize=7.8)
    # electron-transfer arrow (uphill in raw frontier orbitals)
    axa.annotate("", xy=(1 - bw, os3_lumo), xytext=(bw, fadh2_homo),
                 arrowprops=dict(arrowstyle="-|>", color=C["purple"], linewidth=2.2))
    axa.text(0.5, (fadh2_homo + os3_lumo) / 2 + 0.04, "e⁻", ha="center", va="bottom",
             color=C["purple"], fontsize=12, fontweight="bold")
    axa.text(0.5, os3_lumo + 0.13, f"raw Δε = {raw_delta:+.3f} eV (uphill)", ha="center",
             va="bottom", fontsize=7.3, color=C["purple"])

    axa.text(0.02, 0.97,
             "Exp-anchored: +466 mV (−0.47 eV) downhill\n"
             "[E°(Os)+200 − E°(FAD-GDH)−266 mV vs SHE]\n"
             "raw −0.91 eV = PCM/speciation → Fig 5",
             transform=axa.transAxes, fontsize=6.4, va="top", ha="left",
             bbox=dict(boxstyle="round,pad=0.35", fc="#eef6ff", ec=C["blue"], alpha=0.92))
    axa.text(0.98, 0.03,
             f"PCET E°(FAD/FADH₂) = {e_pcet_ph7:.0f} mV vs SHE @pH7\n"
             f"(exp −208; Δ{pcet['delta_vs_exp_pH7_mV']:.0f} mV → flavin clean in implicit DFT)",
             transform=axa.transAxes, fontsize=6.4, va="bottom", ha="right",
             bbox=dict(boxstyle="round,pad=0.35", fc="#eefaf2", ec=C["green"], alpha=0.92))
    axa.set_xlim(-0.55, 1.55)
    axa.set_ylim(-5.75, -3.55)
    axa.set_xticks([])
    axa.set_ylabel("Orbital energy (eV)")
    axa.set_title("(a) Anode → mediator electron-transfer cascade")
    axa.grid(True, axis="y", alpha=0.25)

    # ---- (b) Hammett LFER ----
    cx = series["complexes"]
    lbl = {"nme2": "NMe₂", "nh2": "NH₂", "ome": "OMe", "dmbpy": "Me", "bpy": "H",
           "dcbpy": "COOH", "no2": "NO₂", "cf3": "CF₃", "so2cf3": "SO₂CF₃"}
    sig = np.array([c["sigma_para"] for c in cx])
    dered = np.array([c["dE_red_eV"] for c in cx])
    casc = np.array([c["cascade_delta_eV"] for c in cx])
    names = [c["name"] for c in cx]
    _close(casc[names.index("bpy")], -0.9093, 0.005, "① cascade(H)")
    _close(casc[names.index("so2cf3")], -0.2269, 0.005, "① cascade(SO₂CF₃)")
    _close(casc[names.index("nme2")], -1.5013, 0.005, "① cascade(NMe₂)")

    # Reference Hammett LFER = classic monosubstituents OMe→NO₂ (the linear regime).
    # Excluded from the fit: NMe₂/NH₂ (σ⁻ donor-resonance saturation) and the inert
    # CF₃-family design picks (high-σ flattening) — both overlaid as called-out points.
    ref = ["ome", "dmbpy", "bpy", "dcbpy", "no2"]
    ri = [names.index(n) for n in ref]
    slope, intercept = np.polyfit(sig[ri], dered[ri], 1)
    r2 = np.corrcoef(sig[ri], dered[ri])[0, 1] ** 2
    _close(slope, -0.93, 0.03, "① LFER slope (OMe→NO₂)")
    xs = np.linspace(sig[ri].min() - 0.05, 1.0, 50)
    axb.plot(xs, slope * xs + intercept, color=C["grey"], lw=1.2, ls="--", zorder=1,
             label=f"ΔE_red LFER  {slope:.2f} eV/σ (r²={r2:.2f})")

    axb.scatter(sig, dered, s=42, color=C["blue"], zorder=3, label="ΔE_red(III→II)")
    axb.scatter(sig, casc, s=42, marker="s", color=C["red"], zorder=3, label="cascade Δ")
    # mark unstable NO₂ with an open ring
    i_no2 = names.index("no2")
    axb.scatter(sig[i_no2], casc[i_no2], s=140, facecolors="none", edgecolors="k", lw=1.1, zorder=4)
    axb.scatter(sig[i_no2], dered[i_no2], s=140, facecolors="none", edgecolors="k", lw=1.1, zorder=4)

    ann = {
        "nme2": ("donor saturation", (2, 8)),
        "bpy": ("H (ref)", (5, -11)),
        "cf3": ("CF₃ inert", (-12, -16)),
        "so2cf3": ("SO₂CF₃ optimum (inert)", (-6, -16)),
        "no2": ("NO₂ unstable", (-4, 9)),
    }
    for n, (txt, off) in ann.items():
        i = names.index(n)
        axb.annotate(txt, (sig[i], casc[i]), textcoords="offset points",
                     xytext=off, fontsize=6.6, color="k", ha="right" if off[0] < 0 else "left")
    # plain substituent labels on ΔE_red points
    for i, n in enumerate(names):
        axb.annotate(lbl[n], (sig[i], dered[i]), textcoords="offset points", xytext=(3, 4), fontsize=6.3, color=C["blue"])

    axb.axvspan(-0.9, -0.55, color=C["yellow"], alpha=0.18, zorder=0)  # donor-saturation regime
    axb.set_ylim(-5.5, 0.5)
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
    turnover = ket["turnover_s"]
    _close(sc["literature λ"]["margin_vs_turnover"], 1.385, 0.05, "③ lit-λ margin")
    _close(fo["margin_vs_turnover_by_dG_sign"]["dG=0"], 25.165, 0.1, "③ FO-DFT margin")
    _close(fo["t_ij_eV"], 0.005462, 1e-4, "③ FO-DFT t_ij")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(9.6, 4.3))

    # ---- (a) coupling ladder |t_ij| ----
    bars = [
        ("Cu–Co\n(crude ΔSCF)", t["Cu-Co"], C["grey"]),
        ("Cu–Co\n(FO-DFT)", fo["t_ij_eV"], C["red"]),
        ("Co–Ce", t["Co-Ce"], C["blue"]),
        ("Ce–C", t["Ce-C"], C["green"]),
    ]
    xs = np.arange(len(bars))
    axa.bar(xs, [b[1] for b in bars], color=[b[2] for b in bars], width=0.62, zorder=3)
    for x, (_, v, _c) in zip(xs, bars):
        axa.text(x, v * 1.12, f"{v:.4f}", ha="center", va="bottom", fontsize=7)
    axa.set_yscale("log")
    axa.set_xticks(xs)
    axa.set_xticklabels([b[0] for b in bars])
    axa.set_ylabel("electronic coupling |t$_{ij}$| (eV)")
    axa.set_title("(a) ZIF Cu–Co–Ce coupling — Cu–Co is the bottleneck")
    axa.set_ylim(5e-4, 0.4)
    axa.annotate("rate-limiting hop", xy=(0.5, fo["t_ij_eV"]), xytext=(1.4, 0.05),
                 fontsize=7, arrowprops=dict(arrowstyle="->", color="k", lw=0.8))

    # ---- (b) k_DET margin vs turnover ----
    order = ["canon λ=0.7 (old assumption)", "literature λ", "computed λ (B3LYP, Co over-est)", "Ru-swap (Co→Ru, computed)"]
    disp = ["canon λ=0.7\n(withdrawn)", "literature λ\n(2.0/1.4/1.0)", "computed λ\n(B3LYP)", "Ru-swap\n(Co→Ru)"]
    margins = [sc[k]["margin_vs_turnover"] for k in order]
    cols = [C["grey"], C["orange"], C["grey"], C["green"]]
    xs = np.arange(len(order))
    axb.bar(xs, margins, color=cols, width=0.6, zorder=3)
    for x, m in zip(xs, margins):
        axb.text(x, m * (1.4 if m >= 1 else 0.5), f"×{m:.3g}", ha="center",
                 va="bottom" if m >= 1 else "top", fontsize=7)

    # FO-DFT rigorous range as an error bar on top of the literature-λ column
    fo_lo = fo["margin_vs_turnover_by_dG_sign"]["dG=+gap"]
    fo_hi = fo["margin_vs_turnover_by_dG_sign"]["dG=-gap"]
    fo_mid = fo["margin_vs_turnover_by_dG_sign"]["dG=0"]
    axb.errorbar([1], [fo_mid], yerr=[[fo_mid - fo_lo], [fo_hi - fo_mid]], fmt="D",
                 color=C["red"], ms=6, capsize=4, lw=1.4, zorder=5,
                 label=f"FO-DFT range ×{fo_lo:.2g}–{fo_hi:.0f}\n(×{fo_mid:.0f} at ΔG=0)")

    axb.axhline(1.0, color="k", lw=1.1, ls="--", zorder=2)
    axb.text(len(order) - 0.5, 1.25, "enzymatic turnover (10³ s⁻¹)", ha="right", va="bottom", fontsize=7)
    axb.set_yscale("log")
    axb.set_xticks(xs)
    axb.set_xticklabels(disp, fontsize=7)
    axb.set_ylabel("k$_{DET}$ margin vs turnover  (×)")
    axb.set_title("(b) DET rate is λ-sensitive & borderline")
    axb.set_ylim(1e-4, 1e6)
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
    micro = {r["name"]: r for r in _load("microsolvation.json")["results"]}
    wb = {f["name"]: f for f in _load("wb97x_speciation.json")["forms"]}

    k0 = micro["mediator_k0_clwaters"]["cascade_delta_eV"]
    kseries = [
        (0, micro["mediator_k0_clwaters"]["cascade_delta_eV"]),
        (1, micro["mediator_k1_clwaters"]["cascade_delta_eV"]),
        (2, micro["mediator_k2_clwaters"]["cascade_delta_eV"]),
        (3, micro["mediator_k3_clwaters"]["cascade_delta_eV"]),
    ]
    aqua_shift = micro["aqua_meim_h2o"]["cascade_delta_eV"] - k0
    bisim_shift = micro["bisim_meim2"]["cascade_delta_eV"] - k0
    n6 = micro["aquo_n6_innershell"]["dE_red_eV"]
    n18 = micro["aquo_n18_twoshell"]["dE_red_eV"]
    grp8 = n18 - n6
    _close(k0, -0.908, 0.01, "② chloro k0")
    _close(aqua_shift, 0.510, 0.02, "② aqua speciation shift")
    _close(bisim_shift, 0.299, 0.02, "② bis-Im speciation shift")
    _close(grp8, 0.982, 0.02, "② group-8 n6→n18")

    fig, (axa, axb) = plt.subplots(1, 2, figsize=(9.6, 4.3))

    # ---- (a) explicit Cl⁻-water series ----
    kx = np.array([k for k, _ in kseries])
    ky = np.array([v for _, v in kseries])
    slope, intercept = np.polyfit(kx, ky, 1)
    axa.plot(kx, slope * kx + intercept, color=C["grey"], lw=1.2, ls="--",
             label=f"{slope:.3f} eV / water")
    axa.scatter(kx, ky, s=48, color=C["blue"], zorder=3)
    for k, v in kseries:
        axa.annotate(f"{v:.3f}", (k, v), textcoords="offset points", xytext=(4, 6), fontsize=6.8)
    closed = ky[-1] - ky[0]
    axa.set_xticks(kx)
    axa.set_xlabel("explicit H₂O on Cl⁻ ligand (k)")
    axa.set_ylabel("cascade Δ (eV)")
    axa.set_title(f"(a) Explicit microsolvation\n3 H₂O close {closed:+.2f} eV (~22% of gap)")
    axa.legend(loc="lower right", frameon=False)

    # ---- (b) speciation shift (B3LYP cascade-Δ vs ωB97X ΔE_red) + group-8 benchmark ----
    species = ["aqua", "bis-Im"]
    b3 = [aqua_shift, bisim_shift]
    wbsh = [abs(wb["aqua"]["shift_vs_chloro_eV"]), abs(wb["bisim"]["shift_vs_chloro_eV"])]
    xs = np.arange(len(species))
    w = 0.36
    axb.bar(xs - w / 2, b3, width=w, color=C["blue"], label="B3LYP |Δ cascade|", zorder=3)
    axb.bar(xs + w / 2, wbsh, width=w, color=C["sky"], label="ωB97X |Δ(ΔE_red)|", zorder=3)
    for x, v in zip(xs - w / 2, b3):
        axb.text(x, v + 0.012, f"{v:.2f}", ha="center", fontsize=6.8)
    for x, v in zip(xs + w / 2, wbsh):
        axb.text(x, v + 0.012, f"{v:.2f}", ha="center", fontsize=6.8)

    # group-8 PCM benchmark bar (separate category)
    gx = len(species)
    axb.bar([gx], [grp8], width=w * 1.3, color=C["orange"], zorder=3, label="[Os(H₂O)₆] n6→n18")
    axb.text(gx, grp8 + 0.012, f"{grp8:.2f}", ha="center", fontsize=6.8)

    axb.axhline(0, color="k", lw=0.6)
    axb.set_xticks(list(xs) + [gx])
    axb.set_xticklabels(species + ["group-8\nPCM error"])
    axb.set_ylabel("shift vs chloro / 2nd-shell shift (eV)")
    axb.set_title("(b) Speciation is functional-robust;\n[Os(H₂O)₆] recovers the ~1 V group-8 PCM error")
    axb.legend(loc="upper left", frameon=False)
    axb.set_ylim(0, 1.15)

    fig.tight_layout()
    out = PAPER_FIG_DIR / "fig5_solvation_pcm.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}")


# ─────────────────────────────────────────────────────────────────────────────
# Fig S1 — tunneling β·d ensemble robustness (SI)
# ─────────────────────────────────────────────────────────────────────────────
def figS1() -> None:
    te = _load("tunneling_ensemble.json")
    mean, std = te["beta_d_mean"], te["beta_d_std"]
    single = te["beta_d_single_snapshot_AF3"]
    gating = te["conformational_gating_factor"]
    nfr = te["n_valid_frames"]

    fig, ax = plt.subplots(figsize=(5.2, 4.0))
    ax.axhspan(mean - std, mean + std, color=C["blue"], alpha=0.15, label=f"ensemble ±σ ({mean:.2f}±{std:.2f})")
    ax.errorbar([1], [mean], yerr=[std], fmt="o", color=C["blue"], ms=9, capsize=5, lw=1.6,
                label=f"MD ensemble (n={nfr})")
    ax.scatter([0], [single], s=90, marker="D", color=C["red"], zorder=4, label=f"AF3 single snapshot ({single:.2f})")
    ax.set_xlim(-0.6, 1.6)
    ax.set_xticks([0, 1])
    ax.set_xticklabels(["static\n(AF3)", "dynamic\n(MD)"])
    ax.set_ylabel("tunneling decay β·d (Beratan–Onuchic)")
    ax.set_title(f"Tunneling path is thermally robust\nconformational gating ×{gating:.2f} (modest)")
    ax.legend(loc="upper right", frameon=False, fontsize=7)
    fig.tight_layout()
    out = PAPER_FIG_DIR / "figS1_betad_ensemble.png"
    fig.savefig(out)
    plt.close(fig)
    print(f"  ✓ {out.relative_to(REPO_ROOT)}")


def main() -> int:
    PAPER_FIG_DIR.mkdir(parents=True, exist_ok=True)
    print("Building Стаття 1 figures from cache (no DFT) …")
    fig3()
    fig4()
    fig5()
    figS1()
    print("Done — all canon cross-checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
