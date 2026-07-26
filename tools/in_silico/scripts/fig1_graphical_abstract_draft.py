#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fig 1 graphical-abstract — code-schematic DRAFT (layout reference for BioRender).

NOT the final art: a matplotlib block diagram that fixes the LAYOUT, the elements,
the arrows and the canon numbers (cascade +574 mV; E°(Os) +309, E°(FAD-GDH) −265
vs SHE) so a BioRender / Illustrator pass has an exact, drift-free reference.

Conveys the two patentable synergies (patent_claims_draft.md):
  A) one EBFC = power source AND zero-instrumental-noise sensor (delta_t → Lorenz)
  B) one gyroid = xylem-integration + isoelastic match + metal-xylem EBFC electrode

    mamba run -n silken_md python tools/in_silico/scripts/fig1_graphical_abstract_draft.py
"""
import sys
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import PAPER_DIR, REPO_ROOT

OUT = PAPER_DIR / "figures" / "fig1_graphical_abstract_draft.png"

C = {"anode": "#c44", "med": "#e8a", "cath": "#48a", "ti": "#aaa",
     "xylem": "#6b4", "elec": "#fc3", "box": "#f4f4f4"}


def box(ax, x, y, w, h, label, fc, fs=9):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                fc=fc, ec="black", lw=1.2, zorder=3))
    ax.text(x + w / 2, y + h / 2, label, ha="center", va="center",
            fontsize=fs, zorder=4, wrap=True)


def arrow(ax, x1, y1, x2, y2, color="black", lw=2, style="-|>"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style,
                                 mutation_scale=16, color=color, lw=lw, zorder=2))


def main() -> int:
    fig, ax = plt.subplots(figsize=(12, 5.2))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 5.2)
    ax.axis("off")

    # ── title banner ──
    ax.text(6, 4.95, "Self-powered EBFC tree sensor — first-principles electron-transfer energetics",
            ha="center", va="top", fontsize=11, weight="bold")

    # ── LEFT: tree + 3-zone gyroid anchor in xylem (synergy B) ──
    ax.add_patch(FancyBboxPatch((0.3, 0.6), 1.5, 3.7, boxstyle="round,pad=0.05",
                                fc=C["xylem"], ec="black", lw=1, alpha=0.35, zorder=1))
    ax.text(1.05, 4.05, "Tree\nxylem", ha="center", va="center", fontsize=9, style="italic")
    box(ax, 1.55, 2.9, 1.5, 0.7, "Zone 1\nANODE\n(gyroid)", "#e7b7b7", 8)
    box(ax, 1.55, 2.0, 1.5, 0.7, "Zone 2\nseal/PEEK", "#e7e7c7", 8)
    box(ax, 1.55, 1.1, 1.5, 0.7, "Zone 3\nCATHODE", "#b7c7e7", 8)
    ax.text(2.3, 0.75, "Ti-6Al-4V gyroid (65%)\nxylem + isoelastic + electrode",
            ha="center", va="center", fontsize=7, style="italic")

    # ── CENTER: electron cascade (the paper's content) ──
    yc = 3.25
    box(ax, 3.4, yc, 1.25, 0.8, "glucose\n→ FAD-GDH", "#e7b7b7", 8)
    box(ax, 5.05, yc, 1.35, 0.8, "FADH₂\nE° −265 mV", "#e7b7b7", 8)
    box(ax, 6.8, yc, 1.35, 0.8, "Os-PVI\nmediator\n+309 mV", C["med"], 8)
    box(ax, 8.55, yc, 1.45, 0.8, "ZIF cathode\nO₂ → H₂O", "#b7c7e7", 8)
    for x1, x2 in [(4.65, 5.05), (6.4, 6.8), (8.15, 8.55)]:
        arrow(ax, x1, yc + 0.4, x2, yc + 0.4, C["elec"], 2.5)
    ax.text(6.7, yc + 1.05, "cascade  +574 mV / −0.574 eV (downhill, verified E°s)",
            ha="center", fontsize=8, color="#a40", weight="bold")
    ax.text(6.7, yc - 0.3, "e⁻  (Beratan–Onuchic tunnelling β·d = 2.05)",
            ha="center", fontsize=7.5, style="italic")

    # ── RIGHT-LOWER: power + sensor synergy (A) ──
    ax.text(7.4, 2.25, "ONE EBFC  =  power  +  zero-noise sensor", ha="center",
            fontsize=9, weight="bold", color="#206")
    box(ax, 3.4, 1.2, 1.5, 0.7, "EBFC\n~0.5 V", "#ffe7b7", 8)
    box(ax, 5.1, 1.2, 1.6, 0.7, "supercap\ncharge Δt", "#ffe7b7", 8)
    box(ax, 6.9, 1.2, 1.4, 0.7, "MCU +\nLoRa mesh", C["box"], 8)
    box(ax, 8.5, 1.2, 1.7, 0.7, "Lorenz attractor\n→ health", "#d7ecd7", 8)
    for x1, x2 in [(4.9, 5.1), (6.7, 6.9), (8.3, 8.5)]:
        arrow(ax, x1, 1.55, x2, 1.55, "black", 1.8)
    ax.text(5.9, 0.95, "Δt (charge-time) IS the physiological signal — no separate transducer",
            ha="center", fontsize=7.5, style="italic")

    # cascade powers the EBFC chain (down arrow)
    arrow(ax, 4.0, yc, 4.0, 1.9, C["anode"], 1.5, "-|>")

    fig.tight_layout()
    fig.savefig(OUT, dpi=200, bbox_inches="tight")
    print(f"  wrote {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
