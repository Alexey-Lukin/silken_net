# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.9 — the two test decks of the bench stack (00_07 HW.9, ⚖️ founder 2026-11-15): the LOWER deck with the header FW and
two standoffs on its front, and the UPPER deck with the socket CLP on its back and, there too, the surfaces the standoffs'
end faces meet — one upper deck per name in decks.VARIANTS, because what lies under the faces and under the socket's
holes moves the very threshold the bench measures against (02_01 §3.1, the inset of pos. 12, last ⊕). Nothing else is on
them: no nets, no parts beyond the pair and the standoffs; print — «H1», «H2», the upper deck's name and the kit
number's field — on the working faces only, the base faces carrying mask and nothing else (the bench sheet,
docs/protocols/hardware/deck_stack_gap_bench_sheet.md §2.1, §9). Besides the boards it writes hw9_deck_points.csv, the
sheet's points. The arrangement, the contour, the points and every choice that is ours — decks.py; the land patterns —
footprints.py.

The generator is the source; the boards, the projects and fab/ next to it are its output (hardware design —
CERN-OHL-S-2.0 by the zone map in /NOTICE). Run it with the Python that ships inside KiCad 10 (and Ruby on the PATH — the
node's searcher):

    ~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
        tools/pcb/hw9_stack_test_decks/build_decks.py

(-B keeps __pycache__ out of KiCad.app — written bytecode breaks the bundle's code signature.)

Every check runs on all three boards before fab/ is touched: the decks against the node's searcher, the lower deck's
pads one copper under one finish, each upper deck laid over the lower one (socket pad n over header pad n; under the
posts' axes and the end faces the surfaces its name spells, and the threshold they give against the canon's example),
the sheet's points on the surfaces it probes, KiCad's DRC of each board, the base faces empty in the Gerbers, and the
placement file a fab would read against KiCad's own pads. The boards are written first, because DRC and the placement export read them from disk;
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
KIT_FIELD = "#___"                  # the kit number's write-in field (bench sheet §3: every deck is traced by its number)
# The base faces — a deck lies on the plate by it, the stack is read on it (bench sheet §2.1): mask and nothing else
BASE_FACE = {"lower": ("B_Cu", "B_Mask", "B_Paste", "B_Silkscreen"), "upper": ("F_Cu", "F_Mask", "F_Paste", "F_Silkscreen")}
GERBER_OBJECT = re.compile(r"D0?[123]\*|G36\*")   # a draw, a move-to-draw, a flash or a region: anything on the layer
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


def text(board: pcbnew.BOARD, layer: int, words: str, spot: str) -> None:
    """Print on a deck's working face at decks.print_spots()[spot] — mirrored on the back, so it reads from that side;
    refused unless KiCad's own box of it clears every probed surface (decks.clear_of_supports())."""
    label = pcbnew.PCB_TEXT(board)
    label.SetText(words)
    label.SetPosition(pt(*decks.print_spots()[spot]))
    label.SetLayer(layer)
    label.SetMirrored(layer == pcbnew.B_SilkS)
    label.SetTextSize(pt(0.8, 0.8))
    label.SetTextThickness(pcbnew.FromMM(0.15))
    board.Add(label)
    box = label.GetBoundingBox()
    if not decks.clear_of_supports(*(pcbnew.ToMM(v) for v in (box.GetLeft(), box.GetTop(), box.GetRight(), box.GetBottom()))):
        raise SystemExit(f"{board.GetTitleBlock().GetTitle()}: «{words}» stands on a probed surface or off the board")


def lower() -> pcbnew.BOARD:
    """The header and the standoffs; print on the top (working) face only — the bottom is the base the deck lies on."""
    board = new_board("HW.9 test deck, lower: header FW and two standoffs on the front")
    connector_footprint(board, "FW", "J1", PAIR)
    for i, at in enumerate(STANDOFFS):
        standoff_footprint(board, f"H{i + 1}", at)
    for spot, words in (("H1", "H1"), ("H2", "H2"), ("kit", KIT_FIELD)):
        text(board, pcbnew.F_SilkS, words, spot)
    return board


def upper(name: str) -> pcbnew.BOARD:
    """The socket and the surfaces its name spells; print on the back (working) face only — the top is the base face
    the stack is read on."""
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
    # the full name is the title block's; the corner holds four letters
    for spot, words in (("H1", "H1"), ("H2", "H2"), ("name", f"U-{name.upper()}"), ("kit", KIT_FIELD)):
        text(board, pcbnew.B_SilkS, words, spot)
    return board


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


def surface_at(board: pcbnew.BOARD, x: float, y: float, back: bool = True) -> tuple:
    """(copper, mask opened) on one face of a board at a point — by whatever KiCad finds there, shapes and pads alike."""
    items = [*board.GetDrawings(), *(pad for fp in board.GetFootprints() for pad in fp.Pads())]
    layers = (pcbnew.B_Cu, pcbnew.B_Mask) if back else (pcbnew.F_Cu, pcbnew.F_Mask)
    return tuple(any(item.IsOnLayer(layer) and item.HitTest(pt(x, y)) for item in items) for layer in layers)


def check_lower_pads(low: pcbnew.BOARD) -> None:
    """Bench sheet §9 p. 5, the premise «the copper under the header and under the standoffs is the same»: every pad of
    the lower deck is on the one front copper layer with its mask opened, so the board's one finish covers them all."""
    for fp in low.GetFootprints():
        for pad in fp.Pads():
            if not (pad.IsOnLayer(pcbnew.F_Cu) and pad.IsOnLayer(pcbnew.F_Mask)
                    and not pad.IsOnLayer(pcbnew.B_Cu) and not pad.IsOnLayer(pcbnew.B_Mask)):
                raise SystemExit(f"lower deck: a pad of {fp.GetReference()} is not front copper under an opened mask")


def check_points(low: pcbnew.BOARD, uppers: dict, rows: list) -> None:
    """The bench sheet's points on copper, on what KiCad has on the boards: the pads and the standoffs' ring on the lower
    deck's front are bare copper; on each upper deck's back the socket's pads are, and the disc and the strip are the
    surfaces its name spells."""
    for name, deck, _face, x, y in rows:
        if deck == "lower" and not name.startswith("Z_A"):
            boards, want = {"lower": low}, {"lower": (True, True)}
        elif deck == "upper" and not name.startswith("Z_E"):
            boards = uppers
            spelled = {v: [SURFACES[s] for s in decks.variant(v)] for v in uppers}
            want = {v: (True, True) if name.startswith("Z_pad") else spelled[v][0 if name.startswith("Z_disc") else 1] for v in uppers}
        else:
            continue
        for v, board in boards.items():
            if surface_at(board, x, y, back=deck == "upper") != want[v]:
                raise SystemExit(f"point {name} on {v}: (copper, mask opened) = {surface_at(board, x, y, deck == 'upper')}, "
                                 f"the sheet probes {want[v]}")


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


def gerbers(stem: str, out: Path) -> dict:
    """{file name: text} — Gerbers and drill as text, KiCad's time stamps replaced by the title block's date, so that a
    rerun changes nothing; refused if the deck's base face carries anything at all on copper, mask, paste or print (a
    mask layer draws its OPENINGS — empty is mask everywhere)."""
    out.mkdir(parents=True)
    for args in (("gerbers", "--no-x2", "--layers", "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts"),
                 ("drill", "--format", "excellon")):
        subprocess.run([str(KICAD_CLI), "pcb", "export", *args, "--output", f"{out}/", str(HERE / f"{stem}.kicad_pcb")],
                       check=True, capture_output=True, text=True)
    files = {f.name: STAMP.sub(rf"{DATE}\g<1>00:00:00", f.read_text()) for f in sorted(out.iterdir())}
    for layer in BASE_FACE["lower" if stem.endswith("lower") else "upper"]:
        body = next((t for n, t in files.items() if n.startswith(f"{stem}-{layer}.")), None)
        if body is None:
            raise SystemExit(f"{stem}: KiCad wrote no Gerber of the base face's {layer} — nothing to hold empty")
        if GERBER_OBJECT.search(body):
            raise SystemExit(f"{stem}: the base face's {layer} is not empty — the bench sheet (§2.1) needs mask and nothing else")
    return files


def fabrication(stem: str, files: dict, cpl: str, parts: str) -> None:
    """fab/<board>/: the Gerbers and drill gerbers() checked, the placement file placement() checked, the bill of materials."""
    folder = HERE / "fab" / stem / "gerbers"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.iterdir():
        old.unlink()
    for name, body in files.items():
        (folder / name).write_text(body)
    (folder.parent / f"{stem}_cpl.csv").write_text(cpl)
    (folder.parent / f"{stem}_bom.csv").write_text(parts)


def points_file(rows: list) -> str:
    """The bench sheet's points (§9 p. 2): in the frame above, and from the two edges that meet at the cut corner (the key,
    at (min x, min y)): the SHORT edge by H1 (x = min x) and the LONG edge along the standoffs, away from the pair
    (y = min y). A deck turned over keeps that corner on those two edges, so the distances hold on either face."""
    xs, ys = [x for x, _ in outline()], [y for _, y in outline()]
    text = io.StringIO()
    w = csv.writer(text, lineterminator="\n")
    w.writerow(("Point", "Deck", "Face", "X mm", "Y mm", "From the short edge at the key mm", "From the long edge at the key mm"))
    for name, deck, face, x, y in rows:
        w.writerow((name, deck, face, f"{x:.3f}", f"{y:.3f}", f"{x - min(xs):.3f}", f"{y - min(ys):.3f}"))
    return text.getvalue()


def main() -> int:
    node = decks.node_layout()
    low = lower()
    uppers = {name: upper(name) for name in VARIANTS}
    boards = {"hw9_deck_lower": low, **{f"hw9_deck_upper_{name}": board for name, board in uppers.items()}}
    rows = decks.points(node)
    check_node(low, node)
    check_lower_pads(low)
    deltas = {name: check_stack(low, uppers[name], name) for name in VARIANTS}
    check_points(low, uppers, rows)
    for stem, board in boards.items():
        board.Save(str(HERE / f"{stem}.kicad_pcb"))
        write_project(HERE / f"{stem}.kicad_pro")
        drc_gate(HERE / f"{stem}.kicad_pcb")
    with tempfile.TemporaryDirectory() as tmp:
        files = {stem: (gerbers(stem, Path(tmp) / stem), placement(stem, board, Path(tmp)), bom(board))
                 for stem, board in boards.items()}
    for stem, (layers, cpl, parts) in files.items():
        fabrication(stem, layers, cpl, parts)
    (HERE / "hw9_deck_points.csv").write_text(points_file(rows))
    xs, ys = [x for x, _ in outline()], [y for _, y in outline()]
    print(f"wrote {', '.join(boards)} and hw9_deck_points.csv — every check passed before fab/: the node's searcher, "
          "the lower deck's pads one copper and one finish, each upper deck over the lower one (socket pad n over header "
          "pad n, the spelled surfaces, Δ* against the canon's example), the sheet's points on their surfaces, DRC clean "
          "(0 violations, 0 unconnected) each, the base faces mask and nothing else in the Gerbers, the placement file "
          "against KiCad's pads")
    print(f"  contour {max(xs) - min(xs):.2f} × {max(ys) - min(ys):.2f} mm, one corner cut {KEY:.1f} × {KEY:.1f} (the key), "
          f"{THICKNESS} mm, 2 layers; standoffs H1, H2 {SPAN} apart, the pair {PAIR[1]} off their line, rows along it")
    for name in VARIANTS:
        face, holes = decks.variant(name)
        delta = "—" if deltas[name] is None else f"{deltas[name]:.4f} mm (canon ≈ {decks.CANON_EXAMPLE[name]})"
        print(f"  upper {name}: under the end faces {face}, under the socket's holes {holes}; Δ* at copper "
              f"{decks.COPPER} and no seam {delta}")
    (gx, gy), ((p0x, p0y), (p1x, p1y)) = node["G"], node["P"]
    print(f"  the node's resultants, in this frame (x along H1→H2, y down, towards the pair; the searcher's standoff B is {node['B']}),"
          " unmarked — print stays off the base faces; the points, G among them, are in hw9_deck_points.csv:")
    print(f"    G, the gasket's bead, on the upper deck from above — where the bench's load goes: ({gx:+.3f}, {gy:+.3f})")
    print(f"    P, the pogo pins' resultant, on the lower deck from below — a force up to 1.92 N in the node, not the bench's "
          f"support: ({p0x:+.3f}, {p0y:+.3f}) … ({p1x:+.3f}, {p1y:+.3f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
