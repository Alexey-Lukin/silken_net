#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fig 2 (publication cartoon) — dgrGcGDH AF3 structure + the burial depth of the flavin.

Upgrades the 60_paper_figures.py DRAFT (2D PCA projection) to a real PyMOL cartoon: the buried FAD cofactor and
the N5 → Tyr90 OH burial depth. ⛔ No tunnelling path is drawn (self-review round 1, cluster 6, 2026-10-15): script 28
is a contact-graph search from the phosphate/ribose end of FAD, not a pathway from N5, and the dashes this script
drew from N5 to the route's Cα atoms gave the route an origin it never had.

PyMOL is intentionally NOT in `silken_md` (keeps the conda-lock gate clean):
    mamba create -n pymol_tmp -c conda-forge pymol-open-source -y
    mamba run -n pymol_tmp python tools/in_silico/scripts/fig2_pymol_cartoon.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pymol import cmd, util

from lib.constants import AF3_PDB, PAPER_DIR, REPO_ROOT

OUT = PAPER_DIR / "figures" / "fig2_structure_path_pymol.png"
EXIT_RESI = 90  # Tyr90 — the nearest surface exit of N5 (the burial depth, §3.1); no route residues (cluster 6)

cmd.reinitialize()
cmd.load(str(AF3_PDB), "gdh")
cmd.bg_color("white")
cmd.hide("everything")

# protein cartoon (chain A) — soft, semi-transparent so the buried path reads
cmd.show("cartoon", "polymer")
cmd.color("grey80", "polymer")
cmd.set("cartoon_transparency", 0.4)

# FAD cofactor — sticks, coloured by atom on a yellow carbon
cmd.show("sticks", "resn FAD")
cmd.color("yellow", "resn FAD and elem C")
util.cnc("resn FAD")

# tunnelling-path residues — orange sticks + Cα labels
sel_path = f"chain A and resi {EXIT_RESI}"
cmd.show("sticks", sel_path)
cmd.color("orange", sel_path + " and elem C")
util.cnc(sel_path)
cmd.label(f"chain A and resi {EXIT_RESI} and name CA", '"Tyr90"')

# the burial depth as one dashed line, N5 → Tyr90 OH (the only measured distance this figure carries)
cmd.distance("depth", "resn FAD and name N5", "chain A and resi 90 and name OH")
cmd.hide("labels", "depth")
cmd.color("red", "depth")
cmd.set("dash_width", 4)
cmd.set("label_size", 15)
cmd.set("label_color", "black")
cmd.set("label_outline_color", "white")
cmd.set("label_position", (0, 2.2, 2.5))   # lift labels off the backbone (260/261 & 283/288 are adjacent → collide on-spot)
cmd.set("label_connector", 1)              # leader line from label back to its Cα
cmd.set("label_connector_width", 1)

# orient on the active-site region, slight tilt for depth, render high-res
focus = f"resn FAD or ({sel_path})"
cmd.orient(focus)
cmd.turn("y", 25)
cmd.turn("x", -10)
cmd.zoom(focus, 9)
cmd.set("ray_opaque_background", 0)
cmd.set("antialias", 2)
cmd.ray(2000, 1500)
cmd.png(str(OUT), dpi=300)
print(f"  wrote {OUT.relative_to(REPO_ROOT)}")
