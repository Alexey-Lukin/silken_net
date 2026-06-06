#!/usr/bin/env python
"""Fig 2 (publication cartoon) — dgrGcGDH AF3 structure + Beratan-Onuchic tunnelling path.

Upgrades the 60_paper_figures.py DRAFT (2D PCA projection) to a real PyMOL cartoon:
the buried FAD cofactor + the through-bond electron-exit path
(FAD N5 → Ala261 → Thr260 → Thr283 → Thr288; β·d = 2.05, script 28).

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
PATH_RESI = [261, 260, 283, 288]  # CA hops after FAD N5 (script 28 / OUTLINE §3.1)

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
sel_path = "chain A and resi " + "+".join(map(str, PATH_RESI))
cmd.show("sticks", sel_path)
cmd.color("orange", sel_path + " and elem C")
util.cnc(sel_path)
for rs in PATH_RESI:
    cmd.label(f"chain A and resi {rs} and name CA", f'"{rs}"')

# tunnelling path as red dashes: FAD N5 → each Cα in order
prev = "resn FAD and name N5"
for rs in PATH_RESI:
    nxt = f"chain A and resi {rs} and name CA"
    cmd.distance(f"path_{rs}", prev, nxt)
    prev = nxt
cmd.hide("labels", "path_*")          # keep the dashes, drop the distance numbers
cmd.color("red", "path_*")
cmd.set("dash_width", 4)
cmd.set("label_size", 14)
cmd.set("label_color", "black")
cmd.set("label_outline_color", "white")

# orient on the active-site region, slight tilt for depth, render high-res
focus = f"resn FAD or ({sel_path})"
cmd.orient(focus)
cmd.turn("y", 25)
cmd.turn("x", -10)
cmd.zoom(focus, 9)
cmd.set("ray_opaque_background", 0)
cmd.set("antialias", 2)
cmd.ray(1600, 1200)
cmd.png(str(OUT), dpi=300)
print(f"  wrote {OUT.relative_to(REPO_ROOT)}")
