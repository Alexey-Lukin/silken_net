#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L3 step 3 — aggregate frontier orbital energies from scripts 20 and 21.

Renders the energy ladder diagram that visualises the cascade
    FADH₂  -e⁻-→  Os(II)   (with empty Os(III) accepting orbital below
                            FADH₂'s donating HOMO)
and prints a textual verdict.

Decision criterion (Koopmans approximation in PCM water):

    The electron-donating orbital is HOMO(FADH₂).
    The electron-accepting orbital is LUMO(Os(III)) (= the β-SOMO of the
    open-shell d⁵ complex, which is the lowest unoccupied β-spin orbital).
    For downhill (Marcus-favorable) electron transfer:
        ε_HOMO(FADH₂) > ε_LUMO(Os(III))     (both negative; FADH₂ closer to 0)

Outputs
-------
  * `tools/in_silico/cache/dft/comparison.json`   — combined results
  * `tools/in_silico/cache/dft/energy_ladder.png` — diagrammatic figure
  * stdout                                        — verdict line

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/22_compare_homo_lumo.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, OS_DEVICE_MEDIATOR_LIGAND, REPO_ROOT

FLAV_JSON = DFT_CACHE / "lumiflavin.json"
OS_JSON = DFT_CACHE / "os_complex.json"
OUT_JSON = DFT_CACHE / "comparison.json"
OUT_FIG = DFT_CACHE / "energy_ladder.png"


def main() -> int:
    if not FLAV_JSON.exists() or not OS_JSON.exists():
        sys.exit(f"Missing inputs. Run scripts 20 + 21 first.\n  {FLAV_JSON}\n  {OS_JSON}")

    flav = json.loads(FLAV_JSON.read_text(encoding="utf-8"))
    osj = json.loads(OS_JSON.read_text(encoding="utf-8"))

    # os_complex.json has ONE canonical owner — 21f (the +309 mV 4,4'-dimethyl-bpy device
    # mediator, OS-RECOMPUTE). Scripts 21/21b write their own _nh3/_plain caches; guard here so
    # re-running the wrong one can never silently revert this cascade verdict to plain/NH₃.
    if osj.get("ligand") != OS_DEVICE_MEDIATOR_LIGAND:
        sys.exit(f"CANON: os_complex.json ligand={osj.get('ligand')!r}, expected "
                 f"{OS_DEVICE_MEDIATOR_LIGAND!r} — re-run 21f (dimethyl), not 21/21b.")

    fad_ox_homo = flav["ox"]["HOMO_eV"]
    fad_ox_lumo = flav["ox"]["LUMO_eV"]
    fadh2_homo = flav["red"]["HOMO_eV"]
    fadh2_lumo = flav["red"]["LUMO_eV"]
    os2_homo = osj["os2_plus"]["HOMO_eV"]
    os2_lumo = osj["os2_plus"]["LUMO_eV"]
    os3_homo = osj["os3_plus"]["HOMO_eV"]
    os3_lumo = osj["os3_plus"]["LUMO_eV"]

    # Verdict: HOMO_FADH2 > LUMO_Os(III)
    donor = fadh2_homo
    acceptor = os3_lumo
    delta = donor - acceptor
    favorable = delta > 0

    verdict = "✅ DOWNHILL — electron transfer FAD → Os is energetically favorable" if favorable else \
              "❌ UPHILL — electron transfer FAD → Os is NOT favorable at this level of theory"

    print("=" * 72)
    print("L3 frontier-orbital comparison — FAD vs Os mediator")
    print("=" * 72)
    print(f"Method (FAD):  {flav['method']}")
    print(f"Method (Os):   {osj['method']}")
    print()
    print(f"{'species':<28s}  {'HOMO (eV)':>10s}  {'LUMO (eV)':>10s}  {'gap (eV)':>9s}")
    print("-" * 72)
    print(f"{'FAD (oxidized)':<28s}  {fad_ox_homo:>10.3f}  {fad_ox_lumo:>10.3f}  {fad_ox_lumo - fad_ox_homo:>9.3f}")
    print(f"{'FADH₂ (reduced)':<28s}  {fadh2_homo:>10.3f}  {fadh2_lumo:>10.3f}  {fadh2_lumo - fadh2_homo:>9.3f}")
    os2_label = osj["os2_plus"].get("label", "Os(II)")
    os3_label = osj["os3_plus"].get("label", "Os(III)")
    print(f"{os2_label:<28s}  {os2_homo:>10.3f}  {os2_lumo:>10.3f}  {os2_lumo - os2_homo:>9.3f}")
    print(f"{os3_label:<28s}  {os3_homo:>10.3f}  {os3_lumo:>10.3f}  {os3_lumo - os3_homo:>9.3f}")
    print()
    print("Marcus cascade test:")
    print(f"  ε_HOMO(FADH₂)       = {donor:.3f} eV   (electron donor)")
    print(f"  ε_LUMO(Os(III))     = {acceptor:.3f} eV  (electron acceptor)")
    print(f"  Δε = donor - acceptor = {delta:+.3f} eV")
    print(f"  Direction           : {'donor higher → downhill' if favorable else 'acceptor higher → uphill'}")
    print()
    print(verdict)
    print()

    # Energy ladder figure
    fig, ax = plt.subplots(figsize=(8, 6))
    # Strip species prefix to keep ladder labels compact
    os2_short = os2_label.split()[0] if " " in os2_label else os2_label
    os3_short = os3_label.split()[0] if " " in os3_label else os3_label
    species = [
        ("FAD (ox)", fad_ox_homo, fad_ox_lumo, "#888888"),
        ("FADH₂ (red)", fadh2_homo, fadh2_lumo, "#1f77b4"),
        (os2_short, os2_homo, os2_lumo, "#2ca02c"),
        (os3_short, os3_homo, os3_lumo, "#d62728"),
    ]
    x_positions = np.arange(len(species))
    bar_width = 0.6
    for i, (name, h, lumo, color) in enumerate(species):
        ax.hlines(h, i - bar_width / 2, i + bar_width / 2, colors=color, linewidth=3, label=f"{name} HOMO" if i == 0 else None)
        ax.hlines(lumo, i - bar_width / 2, i + bar_width / 2, colors=color, linewidth=3, linestyles="dashed")
        ax.text(i, h - 0.1, f"{h:.2f}", ha="center", va="top", fontsize=8, color=color)
        ax.text(i, lumo + 0.1, f"{lumo:.2f}", ha="center", va="bottom", fontsize=8, color=color)

    # Arrow from FADH₂ HOMO to Os(III) LUMO (the electron-transfer event)
    ax.annotate(
        "", xy=(3, os3_lumo), xytext=(1, fadh2_homo),
        arrowprops={"arrowstyle": "->", "color": "purple", "linewidth": 2.5},
    )
    ax.text(2, (fadh2_homo + os3_lumo) / 2 + 0.2, "e⁻", ha="center", color="purple", fontsize=12, fontweight="bold")

    ax.set_xticks(x_positions)
    ax.set_xticklabels([s[0] for s in species])
    ax.set_ylabel("Orbital energy (eV)")
    ax.set_title("L3 frontier orbitals — FAD ↔ Os mediator cascade\n(solid: HOMO, dashed: LUMO; arrow = electron transfer)")
    ax.grid(True, axis="y", alpha=0.3)
    ax.axhline(0, color="black", linewidth=0.5)
    fig.tight_layout()
    fig.savefig(OUT_FIG, dpi=140)
    print(f"Wrote diagram: {OUT_FIG.relative_to(REPO_ROOT)}")

    OUT_JSON.write_text(
        json.dumps(
            {
                "donor_homo_eV": donor,
                "acceptor_lumo_eV": acceptor,
                "delta_eV": delta,
                "favorable": favorable,
                "verdict": verdict,
                "fad": flav,
                "os": osj,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Wrote summary: {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
