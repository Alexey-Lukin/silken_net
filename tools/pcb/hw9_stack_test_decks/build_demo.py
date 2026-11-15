# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.9 — the smallest board that puts both land patterns of footprints.py through KiCad's DRC: the header FW on the front
and the socket CLP on the BACK at the same place — the stack seen in plan, the header on top of the lower deck and the
socket under the upper one. It is a proof of the footprints, not a deck: no standoffs, no nets, nothing to order (the
decks are build_decks.py, which imports the project and DRC helpers below; its stack check across two boards covers
the flip check here, and what this run adds is the printout of the gap under the socket).

The generator is the source; the board and the project next to it are its output (hardware design — CERN-OHL-S-2.0 by
the zone map in /NOTICE). Run it with the Python that ships inside KiCad 10:

    ~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
        tools/pcb/hw9_stack_test_decks/build_demo.py

(-B keeps __pycache__ out of KiCad.app — written bytecode breaks the bundle's code signature.)

The run refuses a socket pad that KiCad's flip did not put over the header pad of the same number, fails on any DRC
violation or unconnected item, and prints the plan gap between the socket's pad and the path of the post — numbers with
their sources, the input of the leg «routing rule under the CLP socket»; the rule itself is not judged here.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pcbnew
from decks import CLEARANCE
from footprints import INCH, connector_footprint, post_channel, post_gap

HERE = Path(__file__).resolve().parent
NAME = "hw9_footprint_demo"
BOARD_FILE = HERE / f"{NAME}.kicad_pcb"
PROJECT_FILE = HERE / f"{NAME}.kicad_pro"
# pcbnew.py sits at Contents/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/ — seven up is Contents
KICAD_CLI = Path(pcbnew.__file__).resolve().parents[7] / "MacOS/kicad-cli"

BOARD_W, BOARD_H = 12.0, 12.0            # mm, centred on the pair


def build() -> pcbnew.BOARD:
    # KiCad gives every item a random UUID; a fixed seed keeps a regeneration's diff down to what actually moved
    pcbnew.KIID.SeedGenerator(9)
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    tb = board.GetTitleBlock()
    tb.SetTitle("HW.9 — land patterns of Samtec FW (front) and CLP (back), DRC proof")
    tb.SetCompany("SilkenNet")
    tb.SetRevision("1")
    tb.SetDate("2026-11-15")
    board.GetDesignSettings().m_MinClearance = pcbnew.FromMM(CLEARANCE)
    corners = ((-BOARD_W / 2, -BOARD_H / 2), (BOARD_W / 2, -BOARD_H / 2), (BOARD_W / 2, BOARD_H / 2), (-BOARD_W / 2, BOARD_H / 2))
    for i in range(4):
        edge = pcbnew.PCB_SHAPE(board)
        edge.SetShape(pcbnew.SHAPE_T_SEGMENT)
        edge.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(corners[i][0]), pcbnew.FromMM(corners[i][1])))
        edge.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(corners[(i + 1) % 4][0]), pcbnew.FromMM(corners[(i + 1) % 4][1])))
        edge.SetLayer(pcbnew.Edge_Cuts)
        edge.SetWidth(pcbnew.FromMM(0.10))
        board.Add(edge)

    header = connector_footprint(board, "FW", "J1", (0.0, 0.0))
    socket = connector_footprint(board, "CLP", "J2", (0.0, 0.0), bottom=True)
    # The mate, on what KiCad reports after its own flip: socket pad n on the back, in the same column and on the same
    # side of the centreline as header pad n.
    under = {p.GetNumber(): p for p in socket.Pads()}
    for pad in header.Pads():
        mate = under[pad.GetNumber()]
        (hx, hy), (sx, sy) = pad.GetPosition(), mate.GetPosition()
        if not (mate.IsOnLayer(pcbnew.B_Cu) and pad.IsOnLayer(pcbnew.F_Cu) and hx == sx and hy * sy > 0):
            raise SystemExit(f"pad {pad.GetNumber()}: the socket's pad is not under the header's "
                             f"(header {pcbnew.ToMM(hx)}, {pcbnew.ToMM(hy)} · socket {pcbnew.ToMM(sx)}, {pcbnew.ToMM(sy)})")
    return board


def write_project(path: Path = PROJECT_FILE) -> None:
    """The rules KiCad's DRC reads live in the project, not in the board — written here so that a fresh checkout judges
    the board against the same clearance it was built for. (build_decks.py writes its projects with this too.)"""
    path.write_text(json.dumps({
        "board": {"design_settings": {"rules": {
            "min_clearance": CLEARANCE, "min_track_width": 0.2, "min_copper_edge_clearance": 0.3,
            "min_through_hole_diameter": 0.3, "min_hole_to_hole": 0.25, "min_via_annular_width": 0.13,
            "solder_mask_to_copper_clearance": 0.0},
            # the footprints are defined here, not in a library — «library not configured» describes the design's
            # choice, not a defect
            "rule_severities": {"lib_footprint_issues": "ignore", "lib_footprint_mismatch": "ignore"}}},
        "meta": {"filename": path.name, "version": 3},
        "net_settings": {"classes": [{"name": "Default", "clearance": CLEARANCE, "track_width": 0.2,
                                      "via_diameter": 0.6, "via_drill": 0.3}], "meta": {"version": 4}},
    }, indent=2) + "\n")


def drc_gate(board_file: Path = BOARD_FILE) -> None:
    """Any DRC violation or unconnected item fails the build; the failed board stays, as a diff against the committed one."""
    report = HERE / "drc.json"
    subprocess.run([str(KICAD_CLI), "pcb", "drc", "--format", "json", "--units", "mm", "--severity-all",
                    "--output", str(report), str(board_file)], check=True, capture_output=True, text=True)
    data = json.loads(report.read_text())
    bad = data.get("violations", []) + data.get("unconnected_items", [])
    if bad:
        raise SystemExit(f"DRC failed for {board_file.name}:\n  " +
                         "\n  ".join(f"{v['severity']} {v['type']}: {v['description']}" for v in bad))
    report.unlink()


def main() -> int:
    board = build()
    board.Save(str(BOARD_FILE))
    write_project()
    drc_gate()
    print(f"wrote {BOARD_FILE.name} and {PROJECT_FILE.name} — FW on the front, CLP flipped onto the back, "
          "socket pad n under header pad n for all 10; DRC clean (0 violations, 0 unconnected)")
    pad_inner, post_face, gap = post_gap()
    print("plan gap, socket pad ↔ path of the post (nominal, from the pair's centreline; derived, not printed in a drawing):")
    print(f"  inner edge of a CLP pad   {pad_inner:.4f} mm = .185/2 − .058 in   (CLP footprint REVISION W, sheet 1, FIG 1)")
    print(f"  outer face of a post      {post_face:.4f} mm = .050/2 + .016/2 in (FW print REVISION DG, sheet 1, FIG 1: "
          "rows .050 REF, post .016 SQ REF)")
    print(f"  gap                       {gap:.4f} mm = {gap / INCH:.4f} in")
    print(f"  strip between the inner faces of the two rows of posts: {post_channel():.4f} mm = 2 × (.025 − .008) = "
          f"{post_channel() / INCH:.3f} in (the same two REF numbers)")
    print("  what moves a post against a CLP pad — the sway apart, none of it is toleranced in these drawings:")
    print("    where the socket's body settles on its pads (placement, self-centring) · the post's play in the cavity across "
          "the rows (the CLP print does not dimension the cavity) ·")
    print("    the post's own position (.050 and .016 are REF) · its lean («2° MAX SWAY (EITHER DIRECTION)», FW print, "
          "sheet 1, drawn along the row) · etch and registration of the board's copper")
    print("  the pad beside a post is the pad of the cavity that post enters — the same net: a post against that copper is "
          "a question of stack height, not of a short")
    return 0


if __name__ == "__main__":
    sys.exit(main())
