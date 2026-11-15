# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.9 — the two test decks of the bench stack (00_07 HW.9, ⚖️ founder 2026-11-15): the LOWER deck with the header FW and
two standoffs on its front, and the UPPER deck with the socket CLP on its back and, there too, the surfaces the standoffs'
end faces meet — one upper deck per name in decks.VARIANTS, because what lies under the faces and under the socket's
holes moves the very threshold the bench measures against (02_01 §3.1, the inset of pos. 12, last ⊕). Nothing else is on
them: no nets, no parts beyond the pair and the standoffs; in print only the upper deck's name and the marks of the
node's two resultants where print may stand. The arrangement, the contour and every choice that is ours — decks.py; the
land patterns — footprints.py.

The generator is the source; the boards, the projects and fab/ next to it are its output (hardware design —
CERN-OHL-S-2.0 by the zone map in /NOTICE). Run it with the Python that ships inside KiCad 10 (and Ruby on the PATH — the
node's searcher):

    ~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
        tools/pcb/hw9_stack_test_decks/build_decks.py

(-B keeps __pycache__ out of KiCad.app — written bytecode breaks the bundle's code signature.)

Every check runs on all three boards before fab/ is touched: the decks against the node's searcher, each upper deck laid
over the lower one (socket pad n over header pad n; under the posts' axes and the end faces the surfaces its name spells,
and the threshold they give against the canon's example), KiCad's DRC of each board, and the placement file a fab would
read against KiCad's own pads. The boards are written first, because DRC and the placement export read them from disk;
a board that failed stays in the tree as a diff against the committed one.
"""
from __future__ import annotations

import csv
import io
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import decks
import pcbnew
from build_demo import HERE, KICAD_CLI, drc_gate, write_project
from decks import KEY, PAIR, SPAN, STANDOFFS, SURFACES, VARIANTS, outline
from footprints import COURTYARD_MARGIN, INCH, PARTS, STANDOFF, connector_footprint, courtyard, pads, standoff_footprint

DATE = "2026-11-15"
THICKNESS = 1.6                     # mm — the node's decks (02_01 §3.1 pos. 8); it also keeps the standoff's 1.4 mm spigot
#                                     inside the lower deck. Ours until the order is ruled — a question of that submission
BACK = {"Cu": pcbnew.B_Cu, "Mask": pcbnew.B_Mask}
STAMP = re.compile(r"\d{4}-\d\d-\d\d([T ])\d\d:\d\d:\d\d(?:[+-]\d\d:?\d\d)?")
TICK = (0.2, 0.45)                  # mm — a mark is four ticks round its point, this far out: no print ON the point
CODE_HOME = {"FW": "02_01 §3.1 pos. 12", "CLP": "02_01 §3.1 pos. 12", "standoff": "02_01 §3.1 pos. 25"}


def pt(x: float, y: float) -> pcbnew.VECTOR2I:
    return pcbnew.VECTOR2I(pcbnew.FromMM(x), pcbnew.FromMM(y))


def new_board(title: str) -> pcbnew.BOARD:
    # KiCad gives every item a random UUID; a seed per board keeps a regeneration's diff down to what actually moved
    pcbnew.KIID.SeedGenerator(sum(map(ord, title)))
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    tb = board.GetTitleBlock()
    tb.SetTitle(title)
    tb.SetCompany("SilkenNet")
    tb.SetRevision("1")
    tb.SetDate(DATE)
    ds = board.GetDesignSettings()
    ds.m_MinClearance = pcbnew.FromMM(decks.CLEARANCE)
    ds.SetBoardThickness(pcbnew.FromMM(THICKNESS))
    corners = outline()
    for i in range(len(corners)):
        edge = pcbnew.PCB_SHAPE(board)
        edge.SetShape(pcbnew.SHAPE_T_SEGMENT)
        edge.SetStart(pt(*corners[i]))
        edge.SetEnd(pt(*corners[(i + 1) % len(corners)]))
        edge.SetLayer(pcbnew.Edge_Cuts)
        edge.SetWidth(pcbnew.FromMM(0.10))
        board.Add(edge)
    return board


def mark(board: pcbnew.BOARD, layer: int, x: float, y: float) -> bool:
    """An open cross at (x, y) — if decks.clear_of_supports() lets print stand there; False, and nothing drawn, if not."""
    lo, hi = TICK
    if not decks.clear_of_supports(x - hi, y - hi, x + hi, y + hi):
        return False
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        tick = pcbnew.PCB_SHAPE(board)
        tick.SetShape(pcbnew.SHAPE_T_SEGMENT)
        tick.SetStart(pt(x + dx * lo, y + dy * lo))
        tick.SetEnd(pt(x + dx * hi, y + dy * hi))
        tick.SetLayer(layer)
        tick.SetWidth(pcbnew.FromMM(0.15))
        board.Add(tick)
    return True


def lower(node: dict) -> tuple:
    """(board, [marked?] per P): the header and the standoffs; on the BACK — where the pogo pins push — the marks of P."""
    board = new_board("HW.9 test deck, lower: header FW and two standoffs on the front")
    connector_footprint(board, "FW", "J1", PAIR)
    for i, at in enumerate(STANDOFFS):
        standoff_footprint(board, f"H{i + 1}", at)
    return board, [mark(board, pcbnew.B_SilkS, *p) for p in node["P"]]


def upper(name: str, node: dict) -> tuple:
    """(board, marked?): the socket and the surfaces its name spells; on the FRONT — where the gasket's bead presses —
    the name (decks.label_at()) and the mark of G."""
    face, holes = decks.variant(name)
    board = new_board(f"HW.9 test deck, upper {name}: socket CLP on the back; under the end faces {face}, under the holes {holes}")
    connector_footprint(board, "CLP", "J1", PAIR, bottom=True)
    for layer, kind, numbers in decks.upper_surfaces(face, holes):
        shape = pcbnew.PCB_SHAPE(board)
        if kind == "circle":
            shape.SetShape(pcbnew.SHAPE_T_CIRCLE)
            shape.SetCenter(pt(*numbers[:2]))
            shape.SetEnd(pt(numbers[0] + numbers[2], numbers[1]))
        else:
            shape.SetShape(pcbnew.SHAPE_T_RECT)
            shape.SetStart(pt(*numbers[:2]))
            shape.SetEnd(pt(*numbers[2:]))
        shape.SetFilled(True)
        shape.SetWidth(0)
        shape.SetLayer(BACK[layer])
        board.Add(shape)
    label = pcbnew.PCB_TEXT(board)
    label.SetText(f"U-{name.upper()}")                  # the full name is the title block's; the corner holds four letters
    label.SetPosition(pt(*decks.label_at()))
    label.SetLayer(pcbnew.F_SilkS)
    label.SetTextSize(pt(0.8, 0.8))
    label.SetTextThickness(pcbnew.FromMM(0.15))
    board.Add(label)
    box = label.GetBoundingBox()
    if not decks.clear_of_supports(*(pcbnew.ToMM(v) for v in (box.GetLeft(), box.GetTop(), box.GetRight(), box.GetBottom()))):
        raise SystemExit(f"upper {name}: the label stands over a support or off the board")
    return board, mark(board, pcbnew.F_SilkS, *node["G"])


def check_node(low: pcbnew.BOARD, node: dict) -> None:
    """The lower deck against the node's searcher: the arrangement (decks.SPAN · PAIR are its layout, rounded), the
    courtyards it lays out, and the standoff's pad and face — the pad as KiCad has it on the board."""
    def fail(what: str) -> None:
        raise SystemExit(f"decks against the node's searcher: {what}")

    if abs(SPAN - node["span"]) > 0.005 or abs(PAIR[1] - node["pair"][1]) > 0.005:
        fail(f"spacing {node['span']:.4f} and offset {node['pair'][1]:.4f}, the decks have {SPAN} and {PAIR[1]}")
    if abs(PAIR[0] - node["pair"][0]) > 0.05 or node["angle"] > 1.0:
        fail(f"the pair {node['pair'][0]:.3f} off the middle and {node['angle']:.2f}° off the line — not what the decks round")
    if [round(2 * v, 2) for v in courtyard("FW")] != list(node["header"]) or [round(2 * v, 2) for v in courtyard("CLP")] != list(node["socket"]):
        fail("the pair's courtyards are not the ones the node lays out")
    for fp in low.GetFootprints():
        if fp.GetReference().startswith("H"):
            pad = next(iter(fp.Pads()))
            if abs(pcbnew.ToMM(pad.GetSize(pcbnew.F_Cu).x) + 2 * COURTYARD_MARGIN - node["pad_courtyard_d"]) > 1e-6:
                fail(f"{fp.GetReference()}'s pad Ø{pcbnew.ToMM(pad.GetSize(pcbnew.F_Cu).x)} is not the one the node lays out")
    if abs(STANDOFF["body_d"] - node["face_d"]) > 1e-9:
        fail(f"the end face Ø{STANDOFF['body_d']} is not the node's Ø{node['face_d']}")


def surface_at(board: pcbnew.BOARD, x: float, y: float) -> tuple:
    """(copper, mask opened) on the BACK of a board at a point — by whatever KiCad finds there, shapes and pads alike."""
    items = [*board.GetDrawings(), *(pad for fp in board.GetFootprints() for pad in fp.Pads())]
    return tuple(any(item.IsOnLayer(layer) and item.HitTest(pt(x, y)) for item in items) for layer in (pcbnew.B_Cu, pcbnew.B_Mask))


def check_stack(low: pcbnew.BOARD, up: pcbnew.BOARD, name: str) -> float | None:
    """The upper deck `name` over the lower one, contour on contour — two boards, one frame. Returns Δ* of the surfaces
    found (None for a name the canon has no example for)."""
    def fail(what: str) -> None:
        raise SystemExit(f"stack lower + upper {name}: {what}")

    def contour(board: pcbnew.BOARD) -> list:
        return sorted((d.GetStart().x, d.GetStart().y, d.GetEnd().x, d.GetEnd().y)
                      for d in board.GetDrawings() if d.GetLayer() == pcbnew.Edge_Cuts)

    if contour(low) != contour(up):
        fail("the two contours differ")
    parts = {fp.GetReference(): fp for fp in low.GetFootprints()}
    header, socket = parts["J1"], next(iter(up.GetFootprints()))
    centre = header.GetPosition()
    if socket.GetPosition() != centre:
        fail("the socket's centre is not over the header's")
    half = PARTS["FW"]["row_pitch"] / 2 * INCH
    under = {pad.GetNumber(): pad for pad in socket.Pads()}
    holes = set()
    for pad in header.Pads():
        mate, at = under[pad.GetNumber()], pad.GetPosition()
        side = 1 if at.y > centre.y else -1
        if not (pad.IsOnLayer(pcbnew.F_Cu) and mate.IsOnLayer(pcbnew.B_Cu) and mate.GetPosition().x == at.x
                and (mate.GetPosition().y - centre.y) * side > 0):
            fail(f"socket pad {pad.GetNumber()} is not over header pad {pad.GetNumber()}")
        holes.add(surface_at(up, pcbnew.ToMM(at.x), pcbnew.ToMM(centre.y) + side * half))   # under the post behind it
    r = STANDOFF["body_d"] / 2
    faces = set()
    for ref in ("H1", "H2"):
        cx, cy = pcbnew.ToMM(parts[ref].GetPosition().x), pcbnew.ToMM(parts[ref].GetPosition().y)
        faces |= {surface_at(up, cx + r * math.cos(k * math.pi / 4), cy + r * math.sin(k * math.pi / 4)) for k in range(8)}
        faces.add(surface_at(up, cx, cy))
    if len(faces) != 1 or len(holes) != 1:
        fail(f"(copper, mask opened) is not one surface — under the end faces {faces}, under the posts' axes {holes}")
    found, spelled = (faces.pop(), holes.pop()), tuple(SURFACES[state] for state in decks.variant(name))
    if found != spelled:
        fail(f"under the end faces and the posts' axes the deck has {found}, its name spells {spelled}")
    if name not in decks.CANON_EXAMPLE:
        return None
    try:
        delta = decks.threshold(*found)
    except ValueError as e:
        fail(str(e))
    if abs(delta - decks.CANON_EXAMPLE[name]) > 6e-4:
        fail(f"its surfaces give Δ* {delta:.4f} mm, the canon's example for «{name}» is ≈ {decks.CANON_EXAMPLE[name]}")
    return delta


def placement(stem: str, board: pcbnew.BOARD, tmp: Path) -> str:
    """The placement file as hw12_dmn2990ufa_breakout writes it for a fab — KiCad's own `export pos`, in the columns
    Designator · Mid X · Mid Y (Y UP) · Layer · Rotation — returned as the very text that goes into fab/, after that text,
    read back as a fab reads it, has put every pad of the pair and every standoff's hole where KiCad has them. A fab
    reads a Bottom part as KiCad's flip of the pattern (top–bottom) turned by Rotation, counter-clockwise seen from
    above: the socket's 180° is that flip plus a half-turn — the left–right mirror the decks need (README)."""
    pos = tmp / f"{stem}_pos.csv"
    subprocess.run([str(KICAD_CLI), "pcb", "export", "pos", "--format", "csv", "--units", "mm", "--side", "both",
                    "--output", str(pos), str(HERE / f"{stem}.kicad_pcb")], check=True, capture_output=True, text=True)
    text = io.StringIO()
    w = csv.writer(text, lineterminator="\n")
    w.writerow(("Designator", "Mid X", "Mid Y", "Layer", "Rotation"))
    with pos.open(newline="") as src:
        for row in csv.DictReader(src):
            w.writerow((row["Ref"], f"{float(row['PosX']):.4f}mm", f"{float(row['PosY']):.4f}mm",
                        "Top" if row["Side"] == "top" else "Bottom", f"{float(row['Rot']):.0f}"))
    fps = {fp.GetReference(): fp for fp in board.GetFootprints()}
    part_of = {p["value"]: name for name, p in PARTS.items()}
    rows = list(csv.DictReader(io.StringIO(text.getvalue())))
    if sorted(row["Designator"] for row in rows) != sorted(fps):
        raise SystemExit(f"{stem}: the placement file does not list every part")
    for row in rows:
        fp = fps[row["Designator"]]
        x, y, turn = float(row["Mid X"][:-2]), -float(row["Mid Y"][:-2]), math.radians(float(row["Rotation"]))
        flip = -1 if row["Layer"] == "Bottom" else 1
        got = {pad.GetNumber(): pad.GetPosition() for pad in fp.Pads()}
        pattern = [(n, px, py) for n, px, py, _w, _h in pads(part_of[fp.GetValue()])] if fp.GetValue() in part_of else [("", 0.0, 0.0)]
        for n, px, py in pattern:
            want = (x + px * math.cos(turn) + flip * py * math.sin(turn), y - px * math.sin(turn) + flip * py * math.cos(turn))
            if abs(pcbnew.ToMM(got[n].x) - want[0]) > 2e-4 or abs(pcbnew.ToMM(got[n].y) - want[1]) > 2e-4:
                raise SystemExit(f"{stem}: the placement file puts {row['Designator']} pad «{n}» at ({want[0]:.4f}, "
                                 f"{want[1]:.4f}), KiCad has it at ({pcbnew.ToMM(got[n].x):.4f}, {pcbnew.ToMM(got[n].y):.4f})")
    return text.getvalue()


def bom(board: pcbnew.BOARD) -> str:
    part_of = {p["value"]: name for name, p in PARTS.items()}
    text = io.StringIO()
    w = csv.writer(text, lineterminator="\n")
    w.writerow(("Designator", "Part", "Ordering code"))
    for fp in sorted(board.GetFootprints(), key=lambda fp: fp.GetReference()):
        w.writerow((fp.GetReference(), fp.GetValue(), CODE_HOME[part_of.get(fp.GetValue(), "standoff")]))
    return text.getvalue()


def fabrication(stem: str, cpl: str, parts: str) -> None:
    """Gerbers and drill as text — KiCad's time stamps replaced by the title block's date, so that a rerun changes
    nothing — the placement file placement() checked, and the bill of materials."""
    board_file = HERE / f"{stem}.kicad_pcb"
    gerbers = HERE / "fab" / stem / "gerbers"
    gerbers.mkdir(parents=True, exist_ok=True)
    for old in gerbers.iterdir():
        old.unlink()
    for args in (("gerbers", "--no-x2", "--layers", "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts"),
                 ("drill", "--format", "excellon")):
        subprocess.run([str(KICAD_CLI), "pcb", "export", *args, "--output", f"{gerbers}/", str(board_file)],
                       check=True, capture_output=True, text=True)
    for f in gerbers.iterdir():
        f.write_text(STAMP.sub(rf"{DATE}\g<1>00:00:00", f.read_text()))
    (gerbers.parent / f"{stem}_cpl.csv").write_text(cpl)
    (gerbers.parent / f"{stem}_bom.csv").write_text(parts)


def main() -> int:
    node = decks.node_layout()
    low, p_marked = lower(node)
    uppers = {name: upper(name, node) for name in VARIANTS}
    boards = {"hw9_deck_lower": low, **{f"hw9_deck_upper_{name}": board for name, (board, _) in uppers.items()}}
    check_node(low, node)
    deltas = {name: check_stack(low, boards[f"hw9_deck_upper_{name}"], name) for name in VARIANTS}
    for stem, board in boards.items():
        board.Save(str(HERE / f"{stem}.kicad_pcb"))
        write_project(HERE / f"{stem}.kicad_pro")
        drc_gate(HERE / f"{stem}.kicad_pcb")
    with tempfile.TemporaryDirectory() as tmp:
        files = {stem: (placement(stem, board, Path(tmp)), bom(board)) for stem, board in boards.items()}
    for stem, (cpl, parts) in files.items():
        fabrication(stem, cpl, parts)
    xs, ys = [x for x, _ in outline()], [y for _, y in outline()]
    print(f"wrote {', '.join(boards)} — every check passed before fab/: the node's searcher, each upper deck over the lower "
          "one (socket pad n over header pad n, the spelled surfaces, Δ* against the canon's example), DRC clean "
          "(0 violations, 0 unconnected) each, the placement file against KiCad's pads")
    print(f"  contour {max(xs) - min(xs):.2f} × {max(ys) - min(ys):.2f} mm, one corner cut {KEY:.1f} × {KEY:.1f} (the key), "
          f"{THICKNESS} mm, 2 layers; standoffs H1, H2 {SPAN} apart, the pair {PAIR[1]} off their line, rows along it")
    for name in VARIANTS:
        face, holes = decks.variant(name)
        delta = "—" if deltas[name] is None else f"{deltas[name]:.4f} mm (canon ≈ {decks.CANON_EXAMPLE[name]})"
        print(f"  upper {name}: under the end faces {face}, under the socket's holes {holes}; Δ* at copper "
              f"{decks.COPPER} and no seam {delta}")
    (gx, gy), g_marked = node["G"], all(marked for _, marked in uppers.values())
    print(f"  the node's resultants, in this frame (x along H1→H2, y down, towards the pair; the searcher's standoff B is {node['B']}):")
    print(f"    G, the gasket's bead, on the upper deck from above: ({gx:+.3f}, {gy:+.3f}) — "
          + ("marked on its front" if g_marked else "NOT marked: it stands over a standoff's end face"))
    for (px, py), marked in zip(node["P"], p_marked):   # noqa: B905 — KiCad's Python is 3.9: no zip(strict=)
        print(f"    P, the pogo pins' resultant at an extreme split, on the lower deck from below: ({px:+.3f}, {py:+.3f}) — "
              + ("marked on its back" if marked else "NOT marked: no room for print"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
