# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.12 — breakout board for the clamp key DMN2990UFA (X2-DFN0806-3) on a 2.54 mm header, so that the
breadboard measures the IDSS of THE key of candidate P1 instead of waiting for the first PCBA
(00_07 HW.12; why not an adapter — 02_04 §4.1, row HW.12).

The generator is the source; the board, the project and the fabrication outputs next to it are its
output (hardware design — CERN-OHL-S-2.0 by the zone map in /NOTICE; KiCad's S-expressions carry no
comments, so they cannot hold a per-file tag). Run it with the Python that ships inside KiCad 10:

    ~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 \
        tools/pcb/hw12_dmn2990ufa_breakout/build_board.py

Land pattern — Diodes DMN2990UFA datasheet DS35765 Rev. 3-2, p. 5 «Suggested Pad Layout»:
C 0.350 · X 0.200 · X1 0.450 · X2 0.550 · Y 0.375 · Y1 0.475 · Y2 1.000 mm (drain pad on top, the two
small pads below). Pin assignment read from p. 1 «Top View — Package Pin Configuration» (D left, S top
right, G bottom right) and cross-checked against the p. 5 package outline (a bottom view, mirrored):
both readings put G bottom-left and S bottom-right when the drain pad is on top. Pad numbers follow the
SOT-23 MOSFET habit: 1 = G, 2 = S, 3 = D.

Layout choices that are ours, not the datasheet's:
  • header order G · S · D, so that every net routes on the top layer without a via (D goes round the
    top and the right side, S straight down, G down-left);
  • NO copper pour and D kept away from S everywhere but the package itself — the board exists to
    measure a leakage of nanoamperes, and FR4 surface leakage between D and S is a member of that
    measurement (README: order some boards bare as the control);
  • clearance 0.127 mm (5 mil), the smallest the board needs: the datasheet pattern leaves 0.150 mm
    between pads, which a 0.20 mm default clearance would flag.
"""
from __future__ import annotations

import csv
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pcbnew

HERE = Path(__file__).resolve().parent
NAME = "hw12_dmn2990ufa_breakout"
BOARD_FILE = HERE / f"{NAME}.kicad_pcb"
PROJECT_FILE = HERE / f"{NAME}.kicad_pro"
FAB = HERE / "fab"
# Q1 for JLCPCB PCBA: DMN2990UFA-7B = LCSC C151598 (00_07 HW.12); the header is hand-soldered, not in the BOM
JLC_BOM = (("Comment", "Designator", "Footprint", "LCSC Part #"), ("DMN2990UFA-7B", "Q1", "X2-DFN0806-3", "C151598"))
# pcbnew.py sits at Contents/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/ — seven up is Contents
HEADER_LIB = Path(pcbnew.__file__).resolve().parents[7] / "SharedSupport/footprints/Connector_PinHeader_2.54mm.pretty"

BOARD_W, BOARD_H = 12.70, 11.43          # mm — 0.5 × 0.45 in: the pin labels sit below the header's own silk
Q1_AT = (6.175, 3.60)                    # package centre: puts the S pad straight above header pin 2
HEADER_PIN1 = (3.81, 8.00)               # 1 × 3 header along X after a 90° turn
CLEARANCE = 0.127
TRACK_PAD = 0.15                         # where a trace leaves a 0.20 mm pad
TRACK = 0.30

# (number, net, centre relative to Q1, size) — the datasheet pattern, Y2 = Y1 + gap + Y
PADS = (
    ("1", "G", (-0.175, +0.3125), (0.200, 0.375)),
    ("2", "S", (+0.175, +0.3125), (0.200, 0.375)),
    ("3", "D", (0.000, -0.2625), (0.450, 0.475)),
)


def mm(x: float) -> int:
    return pcbnew.FromMM(x)


def pt(x: float, y: float) -> pcbnew.VECTOR2I:
    return pcbnew.VECTOR2I(mm(x), mm(y))


def set_pad_size(pad: pcbnew.PAD, w: float, h: float) -> None:
    try:
        pad.SetSize(pcbnew.F_Cu, pt(w, h))          # KiCad 9+: per-layer padstack
    except TypeError:
        pad.SetSize(pt(w, h))


def set_pad_shape(pad: pcbnew.PAD, shape) -> None:
    try:
        pad.SetShape(pcbnew.F_Cu, shape)
    except TypeError:
        pad.SetShape(shape)


def segment(board, layer, a, b, width, net=None) -> None:
    if layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        item = pcbnew.PCB_TRACK(board)
        item.SetWidth(mm(width))
        if net is not None:
            item.SetNet(net)
    else:
        item = pcbnew.PCB_SHAPE(board)
        item.SetShape(pcbnew.SHAPE_T_SEGMENT)
        item.SetWidth(mm(width))
    item.SetStart(pt(*a))
    item.SetEnd(pt(*b))
    item.SetLayer(layer)
    board.Add(item)


def text(board, s: str, at, size=0.8, layer=pcbnew.F_SilkS) -> None:
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetPosition(pt(*at))
    t.SetLayer(layer)
    t.SetTextSize(pt(size, size))
    t.SetTextThickness(mm(0.15))
    board.Add(t)


def dfn_footprint(board, nets: dict) -> pcbnew.FOOTPRINT:
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("SilkenNet", "Diodes_X2-DFN0806-3"))
    fp.SetReference("Q1")
    fp.SetValue("DMN2990UFA")
    fp.SetAttributes(pcbnew.FP_SMD)
    fp.SetPosition(pt(*Q1_AT))
    for number, net, (dx, dy), (w, h) in PADS:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(number)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
        set_pad_shape(pad, pcbnew.PAD_SHAPE_RECT)
        set_pad_size(pad, w, h)
        pad.SetLayerSet(pad.SMDMask())
        pad.SetPosition(pt(Q1_AT[0] + dx, Q1_AT[1] + dy))
        pad.SetNet(nets[net])
        fp.Add(pad)
    x0, y0 = Q1_AT
    for layer, hx, hy, width in ((pcbnew.F_CrtYd, 0.425, 0.65, 0.05), (pcbnew.F_Fab, 0.30, 0.40, 0.10)):
        corners = ((x0 - hx, y0 - hy), (x0 + hx, y0 - hy), (x0 + hx, y0 + hy), (x0 - hx, y0 + hy))
        for i in range(4):   # no zip(strict=) — KiCad's Python is 3.9
            a, b = corners[i], corners[(i + 1) % 4]
            shape = pcbnew.PCB_SHAPE(fp)
            shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
            shape.SetStart(pt(*a))
            shape.SetEnd(pt(*b))
            shape.SetLayer(layer)
            shape.SetWidth(mm(width))
            fp.Add(shape)
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)
    board.Add(fp)
    return fp


def header_footprint(board, nets: dict) -> pcbnew.FOOTPRINT:
    fp = pcbnew.FootprintLoad(str(HEADER_LIB), "PinHeader_1x03_P2.54mm_Vertical")
    fp.SetReference("J1")
    fp.SetValue("G S D")
    fp.SetOrientationDegrees(90)
    fp.SetPosition(pt(*HEADER_PIN1))
    for i, pad in enumerate(fp.Pads()):
        pad.SetNet(nets[("G", "S", "D")[i]])
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)
    board.Add(fp)
    return fp


def build() -> pcbnew.BOARD:
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    tb = board.GetTitleBlock()
    tb.SetTitle("HW.12 — DMN2990UFA breakout (X2-DFN0806-3 → 2.54 mm)")
    tb.SetCompany("SilkenNet")
    tb.SetRevision("1")
    tb.SetDate("2026-10-05")
    ds = board.GetDesignSettings()
    ds.m_MinClearance = mm(CLEARANCE)
    ds.m_TrackMinWidth = mm(TRACK_PAD)
    nets = {}
    for name in ("G", "S", "D"):
        net = pcbnew.NETINFO_ITEM(board, name)
        board.Add(net)
        nets[name] = net

    corners = ((0, 0), (BOARD_W, 0), (BOARD_W, BOARD_H), (0, BOARD_H))
    for i in range(4):
        segment(board, pcbnew.Edge_Cuts, corners[i], corners[(i + 1) % 4], 0.10)

    dfn_footprint(board, nets)
    header = header_footprint(board, nets)
    pins = {p.GetNumber(): (pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)) for p in header.Pads()}

    qx, qy = Q1_AT
    g_pad = (qx - 0.175, qy + 0.3125)
    s_pad = (qx + 0.175, qy + 0.3125)
    d_pad = (qx, qy - 0.2625)
    # G: down out of the pad, then 45° down-left to header pin 1 — NARROW until it has left S behind
    # (a 0.30 mm track's round cap at the turn sat 0.125 mm from S, under the 0.127 rule)
    g_turn = (g_pad[0], qy + 0.80)
    g_wide = (g_turn[0] - 0.60, g_turn[1] + 0.60)
    g_drop = (pins["1"][0], g_turn[1] + (g_turn[0] - pins["1"][0]))
    segment(board, pcbnew.F_Cu, g_pad, g_turn, TRACK_PAD, nets["G"])
    segment(board, pcbnew.F_Cu, g_turn, g_wide, TRACK_PAD, nets["G"])
    segment(board, pcbnew.F_Cu, g_wide, g_drop, TRACK, nets["G"])
    segment(board, pcbnew.F_Cu, g_drop, pins["1"], TRACK, nets["G"])
    # S: straight down to header pin 2 (the package sits so that the S pad is above it)
    if abs(s_pad[0] - pins["2"][0]) > 1e-6:
        raise SystemExit(f"S pad x {s_pad[0]} is not above header pin 2 x {pins['2'][0]}")
    s_neck = (s_pad[0], qy + 1.00)
    segment(board, pcbnew.F_Cu, s_pad, s_neck, TRACK_PAD, nets["S"])
    segment(board, pcbnew.F_Cu, s_neck, pins["2"], TRACK, nets["S"])
    # D: up over the package, along the right side, then 45° down-left to header pin 3
    d_up = (d_pad[0], 2.00)
    d_right = (10.60, 2.00)
    d_down = (10.60, pins["3"][1] - (10.60 - pins["3"][0]))
    for a, b in ((d_pad, d_up), (d_up, d_right), (d_right, d_down), (d_down, pins["3"])):
        segment(board, pcbnew.F_Cu, a, b, TRACK, nets["D"])

    for label, pin in (("G", "1"), ("S", "2"), ("D", "3")):
        text(board, label, (pins[pin][0], 10.40))
    text(board, "HW.12 DMN2990UFA", (6.35, 0.85), size=0.8)
    # «bar denotes gate and source side» — a dot on the silk, left of the G pad, clear of copper
    segment(board, pcbnew.F_SilkS, (g_pad[0] - 0.60, g_pad[1]), (g_pad[0] - 0.55, g_pad[1]), 0.15)
    return board


def write_project() -> None:
    """The rules KiCad's DRC reads live in the project, not in the board — written here so that a
    fresh checkout judges the board against the same 5-mil clearance it was built for."""
    PROJECT_FILE.write_text(json.dumps({
        "board": {"design_settings": {"rules": {
            "min_clearance": CLEARANCE, "min_track_width": TRACK_PAD, "min_copper_edge_clearance": 0.3,
            "min_through_hole_diameter": 0.3, "min_hole_to_hole": 0.25, "min_via_annular_width": 0.13,
            "solder_mask_to_copper_clearance": 0.0},
            # Q1 is defined here, not in a library — the board embeds it, so «library not configured»
            # describes the design's choice, not a defect
            "rule_severities": {"lib_footprint_issues": "ignore", "lib_footprint_mismatch": "ignore"}}},
        "meta": {"filename": PROJECT_FILE.name, "version": 3},
        "net_settings": {"classes": [{"name": "Default", "clearance": CLEARANCE, "track_width": TRACK,
                                      "via_diameter": 0.6, "via_drill": 0.3}], "meta": {"version": 4}},
    }, indent=2) + "\n")


def kicad_cli() -> Path:
    return Path(pcbnew.__file__).resolve().parents[7] / "MacOS/kicad-cli"


def run(*args: str) -> None:
    subprocess.run([str(kicad_cli()), *args], check=True, capture_output=True, text=True)


def drc_gate() -> None:
    """The build fails on ANY DRC violation or unconnected item — the board is never written out
    for fabrication on a hope. It can fail: the first layout put G's round track cap 0.125 mm from S."""
    report = FAB / "drc.json"
    run("pcb", "drc", "--format", "json", "--units", "mm", "--severity-all", "--output", str(report), str(BOARD_FILE))
    data = json.loads(report.read_text())
    bad = data.get("violations", []) + data.get("unconnected_items", [])
    if bad:
        raise SystemExit("DRC failed:\n  " + "\n  ".join(f"{v['severity']} {v['type']}: {v['description']}" for v in bad))
    report.unlink()


def fabrication() -> None:
    """Gerbers + drill (zipped for upload), placement and BOM in the JLCPCB column names."""
    gerbers = FAB / "gerbers"
    gerbers.mkdir(parents=True, exist_ok=True)
    for old in gerbers.iterdir():
        old.unlink()
    run("pcb", "export", "gerbers", "--no-x2", "--layers",
        "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts", "--output", f"{gerbers}/", str(BOARD_FILE))
    run("pcb", "export", "drill", "--format", "excellon", "--output", f"{gerbers}/", str(BOARD_FILE))
    with zipfile.ZipFile(FAB / f"{NAME}_gerbers.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(gerbers.iterdir()):
            z.write(f, f.name)
    pos = FAB / "pos_kicad.csv"
    run("pcb", "export", "pos", "--format", "csv", "--units", "mm", "--side", "front", "--smd-only",
        "--output", str(pos), str(BOARD_FILE))
    with pos.open(newline="") as src, (FAB / f"{NAME}_cpl.csv").open("w", newline="") as dst:
        w = csv.writer(dst)
        w.writerow(("Designator", "Mid X", "Mid Y", "Layer", "Rotation"))
        for row in csv.DictReader(src):
            w.writerow((row["Ref"], f"{float(row['PosX']):.4f}mm", f"{float(row['PosY']):.4f}mm",
                        "Top" if row["Side"] == "top" else "Bottom", f"{float(row['Rot']):.0f}"))
    pos.unlink()
    with (FAB / f"{NAME}_bom.csv").open("w", newline="") as f:
        csv.writer(f).writerows(JLC_BOM)


def main() -> int:
    board = build()
    board.Save(str(BOARD_FILE))
    write_project()
    FAB.mkdir(exist_ok=True)
    drc_gate()
    fabrication()
    print(f"wrote {BOARD_FILE.name}, {PROJECT_FILE.name} and fab/ (DRC clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
