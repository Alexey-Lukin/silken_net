# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.33 — the test boards of axis 3 of the RF mock-up: the efficiency of an antenna booster on a ground of OUR contour, the
number the ruling «for the small ground we pay in efficiency» (02_01 §5.3, ⚖️ 2026-09-23) stands on and which no evaluation
board measures by construction (docs/protocols/hardware/rf_mockup_bench_sheet.md §0 п.1, §5). Two diameters were ratified —
the sentinel Ø20.37 and Ø19.37 (⚖️ 2026-10-01, re-ratified 2026-10-05; bench sheet §5) — and the sheet asks for both
boosters that fit the contour «where possible» (02_01 §5.2): four boards, one per (booster × diameter).

The generator is the source; the boards, the projects and the fabrication outputs next to it are its output (hardware
design — CERN-OHL-S-2.0 by the zone map in /NOTICE; KiCad's S-expressions carry no comments). Run it with the Python that
ships inside KiCad 10:

    ~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 \
        tools/pcb/hw33_rf_axis3_boards/build_boards.py

Primary sources (Ignion, fetched 2026-10-12 from ignion.io/files/; the PDFs are the vendor's and are NOT kept in the tree —
the numbers below are their transcription, with the page each was read on):
  · NN02-224 datasheet DS_NN02-224 (Last Update January 2024, sha256 b97a356b…4c72) §2.7 «Antenna footprint», p. 6:
    pads A 2.2 × C 3.2 mm, inner gap B 7.8 (outer span 12.2), feed track D 2.0 mm wide from one pad into the ground
    plane area, «Matching network» drawn in the ground plane area, the pads in the clearance area; tolerance ±0.2.
  · NN02-224 user manual UM_NN02-224 (Last Update December 2025, sha256 4474b6f2…2c13) §2.1 / §3, pp. 12–13: body
    12.0 × 3.0 × 2.4 mm; the two pads are fully symmetrical, either can feed — «the other pad … must NOT be grounded».
  · NN02-201 datasheet DS_NN02-201 (Last Update April 2024, sha256 2713aa8a…19a0858d) §2.5 «Antenna footprint», p. 4:
    pads B 1.65 × C 2.3 mm, inner gap A 3.0 (outer span D 6.3), feed from the right-hand pad into the ground plane area;
    tolerance ±0.05. User manual UM_NN02-201 (Last Update December 2025, sha256 95db0170…5ed08fda) §2.1, p. 10: body
    7.0 × 3.0 × 1.0 mm — WIDER than its pads, so the body, not the pads, meets the contour first; §3, p. 11, Fig. 7: the
    pads are symmetrical, «This pad must NOT be grounded».
  · Application note AN_NN02-224_ISM (Last Update March 2021, sha256 5bcc531d…9014): SIX evaluation networks, every one
    read off its schematic, and they differ in topology, not only in values —
      §2.3, p. 7 — 863–870 MHz on 131 × 60 (clearance 11 × 60, booster 8.0 mm from the ground): an L, 30 nH in series
                   from the booster and 20 nH shunt at the port (LQW18AN30NG00 / LQW18AN20NG00), efficiency > 85 %;
      §3.3, p. 11 — 902–928 MHz on 131 × 60: an L, 30 nH series · 39 nH shunt;
      §4.3, p. 15 — 863–928 MHz on 131 × 60: a T, 22 nH series · 8.7 nH shunt · 2.0 pF series;
      §5.3, p. 19 — 863–870 MHz on CR80, 86 × 54 (clearance 11 × 54, so a 75 × 54 ground): a T, 30 nH series · 13 nH
                   shunt · 3 nH series (LQW18AN30NG00 / LQW18AN13NG00 / LQW15AN3N0B80D), efficiency > 60 %;
      §6.3, p. 23 — 902–928 MHz on CR80: a T, 27 nH · 13 nH shunt · 2.4 nH;  §7.3, p. 27 — 863–928 MHz on CR80: a T,
                   24 nH · 7.5 nH shunt · 1.8 pF.
    Not one is a π. The smallest published ground for NN02-224, though, is 40 × 20 from another application note
    (02_01 §5.3: 27 nH · 8.2 nH · 2.0 pF, efficiency 27.1 % at 863 MHz) whose topology this pass did not see — the bench
    starts from those values, and the board takes a π as well as a T.
    The vendor states the values move with every ground and every nearby part; ⛔ they are a starting point for tuning
    on the bench, never ours (bench sheet §5; 02_01 §5.3).

Layout choices that are ours, not the vendor's — each one is a knob below, and each changes the measured number:
  • CLEARANCE = the footprint plus GAP_TO_GROUND 1.0 mm between the pads' inner edge and the ground. The datasheet
    drawings show the pads just inside the clearance area (≈ 1.0–1.5 mm on their scale, not dimensioned); the
    evaluation boards use an 11 mm strip. Ours is the narrowest the footprint allows ON PURPOSE: 02_01 §3.5 leaves the
    booster's clearance uncounted and the RF deck's top side is already over-full, so a product board will not afford
    a wide strip — the board measures the efficiency the product can have. «Narrowest» is not «small»: the segment over
    the chord is printed per board on every run (a third of the disc for NN02-224, a fifth for NN02-201), and that
    area is what 02_01 §3.5 does not count. Price: the number comes out MORE pessimistic than a wide clearance would
    give; a wide-clearance variant is a change of GAP_TO_GROUND, not a new board.
  • 2 layers, FR4 1.6 mm (the deck thickness, 02_01 §3.1 pos. 8 — the decks themselves are 4-layer); ground poured on
    both layers and stitched, so the radiator is a single ground disc — the one-deck proxy the sheet names as its weakest
    link (§9).
  • The feed is a grounded coplanar line, W 1.2 / gap 0.2 mm ≈ 51 Ω on FR4 εr 4.4 (Wadell's conductor-backed CPW; the
    whole run is ≈ 0.07 λ_g at 868 MHz, so the impedance is secondary and the bench tunes the network anyway).
  • Four 0603 sites in the ground area right after the clearance: A shunt · B series · C shunt · D series, so one board
    takes the vendor's T (B C D) or L (B C, D = 0 Ω), or a π (A B C), without a respin; parts are DNP — the values come
    from the VNA (bench sheet §5, step 3).
  • A U.FL (Hirose U.FL-R-SMT-1) at the end of the chain, away from the booster: the feeding cable is the 3-B variant of
    the sheet, and the sheet asks for ferrite chokes on it (§5) — they go on the cable, not on the board.
  • The booster sits at the board's edge, as far from the ground as the contour allows (02_01 §5.2 «on the upper edge»):
    whichever of its pads and its BODY reaches further meets the circle r − EDGE_MARGIN, the body assumed centred on its
    pads (the manuals draw it so and do not dimension the offset).

A placement whose pads or booster body leave the contour inside EDGE_MARGIN raises instead of writing a board; a board that
fails DRC (any violation or unconnected item) is deleted together with its project, and no fabrication file is written.
"""
from __future__ import annotations

import csv
import json
import math
import subprocess
import sys
import zipfile
from pathlib import Path

import pcbnew

HERE = Path(__file__).resolve().parent
# pcbnew.py sits at Contents/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/ — seven up is Contents
KICAD = Path(pcbnew.__file__).resolve().parents[7]
FP_LIB = KICAD / "SharedSupport/footprints"

BOOSTERS = {
    # name: (pad width along the body, pad height, centre-to-centre / 2, sign of the feed pad's x, source, body L × W)
    "NN02-224": (2.2, 3.2, (7.8 + 2.2) / 2, -1, "DS_NN02-224 Jan 2024 §2.7", (12.0, 3.0)),
    "NN02-201": (1.65, 2.3, (3.0 + 1.65) / 2, +1, "DS_NN02-201 Apr 2024 §2.5", (7.0, 3.0)),
}
DIAMETERS = (20.37, 19.37)             # sentinel · second board (bench sheet §5, ⚖️ 2026-10-01 / 2026-10-05)
CHAIN_DIRECTION = {"NN02-224": "across", "NN02-201": "down"}   # the wide booster leaves no vertical room under its feed pad

EDGE_MARGIN = 0.5                       # copper ↔ board edge, placement margin (the DRC rule below is 0.3)
GAP_TO_GROUND = 1.0                     # pads' inner edge ↔ ground pour — OURS, see the header
TRACK = 1.2                             # grounded coplanar line ≈ 51 Ω on FR4 1.6, εr 4.4 (Wadell)
GAP = 0.2                               # its gap to the ground pour = the pour's clearance
CLEARANCE = 0.15
FEED_DROP = 2.6                         # how far into the ground area the line goes before the chain starts
STEP = 2.3                              # chain pitch: node A · series B · node C · series D · U.FL signal pad
VIA = (0.6, 0.3)                        # stitching via: pad · drill
VIA_PITCH = 2.0
SEG = 96                                # polygon segments of the round outline for the zones


def mm(x: float) -> int:
    return pcbnew.FromMM(x)


def pt(x: float, y: float) -> pcbnew.VECTOR2I:
    return pcbnew.VECTOR2I(mm(x), mm(y))


def xy(v) -> tuple:
    return pcbnew.ToMM(v.x), pcbnew.ToMM(v.y)


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


def track(board, a, b, net, width=TRACK, layer=pcbnew.F_Cu) -> None:
    t = pcbnew.PCB_TRACK(board)
    t.SetWidth(mm(width))
    t.SetStart(pt(*a))
    t.SetEnd(pt(*b))
    t.SetLayer(layer)
    t.SetNet(net)
    board.Add(t)


def via(board, at, net) -> None:
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pt(*at))
    v.SetWidth(mm(VIA[0]))
    v.SetDrill(mm(VIA[1]))
    v.SetNet(net)
    board.Add(v)


def text(board, s: str, at, size=0.8, layer=pcbnew.B_SilkS) -> None:
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetPosition(pt(*at))
    t.SetLayer(layer)
    t.SetTextSize(pt(size, size))
    t.SetTextThickness(mm(0.15))
    if layer == pcbnew.B_SilkS:
        t.SetMirrored(True)
    board.Add(t)


def circle_points(r: float, a0: float = 0.0, a1: float = 2 * math.pi, n: int = SEG) -> list:
    return [(r * math.cos(a0 + (a1 - a0) * i / n), r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def zone(board, layer, points, net=None) -> pcbnew.ZONE:
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    outline = z.Outline()
    outline.NewOutline()
    for x, y in points:
        outline.Append(mm(x), mm(y))
    if net is not None:
        z.SetNet(net)
        z.SetLocalClearance(mm(GAP))
        z.SetMinThickness(mm(0.2))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)       # an RF ground: solid, no thermal spokes
        z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    board.Add(z)
    return z


def keepout(board, points) -> None:
    """The clearance area: no pour and no via on either layer; the booster's pads and the feed line may cross it."""
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = zone(board, layer, points)
        z.SetIsRuleArea(True)
        z.SetDoNotAllowZoneFills(True)
        z.SetDoNotAllowVias(True)
        z.SetDoNotAllowTracks(False)
        z.SetDoNotAllowPads(False)
        z.SetDoNotAllowFootprints(False)


def booster_footprint(board, name: str, at: tuple, net_feed) -> tuple:
    w, h, half_pitch, feed_sign, source, (body_l, body_w) = BOOSTERS[name]
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("SilkenNet", f"Ignion_{name}"))
    fp.SetReference("AE1")
    fp.SetValue(name)
    fp.SetAttributes(pcbnew.FP_SMD)
    fp.SetPosition(pt(*at))
    feed_at = None
    for number, sign in (("1", feed_sign), ("2", -feed_sign)):
        pad = pcbnew.PAD(fp)
        pad.SetNumber(number)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
        set_pad_shape(pad, pcbnew.PAD_SHAPE_RECT)
        set_pad_size(pad, w, h)
        pad.SetLayerSet(pad.SMDMask())
        pad.SetPosition(pt(at[0] + sign * half_pitch, at[1]))
        if number == "1":
            pad.SetNet(net_feed)                # pad 2 is the mounting pad: no net, never grounded (UM_NN02-224 §3)
            feed_at = (at[0] + sign * half_pitch, at[1])
        fp.Add(pad)
    ex, ey = max(half_pitch + w / 2, body_l / 2), max(h / 2, body_w / 2)     # pads or body, whichever reaches further
    for layer, hx, hy, width in ((pcbnew.F_CrtYd, ex + 0.25, ey + 0.25, 0.05), (pcbnew.F_Fab, body_l / 2, body_w / 2, 0.10)):
        corners = ((at[0] - hx, at[1] - hy), (at[0] + hx, at[1] - hy), (at[0] + hx, at[1] + hy), (at[0] - hx, at[1] + hy))
        for i in range(4):
            shape = pcbnew.PCB_SHAPE(fp)
            shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
            shape.SetStart(pt(*corners[i]))
            shape.SetEnd(pt(*corners[(i + 1) % 4]))
            shape.SetLayer(layer)
            shape.SetWidth(mm(width))
            fp.Add(shape)
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)
    board.Add(fp)
    return feed_at, source


def library_footprint(board, lib: str, name: str, ref: str, value: str, at: tuple, pad1_toward: tuple,
                      nets: dict) -> pcbnew.FOOTPRINT:
    """Place a library footprint at `at`, turned so that pad 1 points at `pad1_toward` — the angle is chosen by the
    resulting pad position, not by a sign convention of KiCad's rotation that a reader would have to trust."""
    best = None
    for angle in (0, 90, 180, 270):
        fp = pcbnew.FootprintLoad(str(FP_LIB / f"{lib}.pretty"), name)
        fp.SetOrientationDegrees(angle)
        fp.SetPosition(pt(*at))
        p1 = next(p for p in fp.Pads() if p.GetNumber() == "1")
        d = math.dist(xy(p1.GetPosition()), pad1_toward)
        if best is None or d < best[0]:
            best = (d, angle)
    fp = pcbnew.FootprintLoad(str(FP_LIB / f"{lib}.pretty"), name)
    fp.SetOrientationDegrees(best[1])
    fp.SetPosition(pt(*at))
    fp.SetReference(ref)
    fp.SetValue(value)
    for pad in fp.Pads():
        pad.SetNet(nets[pad.GetNumber()])
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)
    board.Add(fp)
    return fp


def pad_at(fp: pcbnew.FOOTPRINT, number: str) -> tuple:
    return xy(next(p for p in fp.Pads() if p.GetNumber() == number).GetPosition())


def build(name: str, dia: float) -> tuple:
    # KiCad gives every item a random UUID and orders some outputs by it, so an unchanged board would come out reshuffled
    # on every run; a seed per board keeps a regeneration's diff down to what actually moved (the gerbers' own
    # timestamps still change — that is KiCad's header, not the copper)
    pcbnew.KIID.SeedGenerator(int(dia * 100) * 7 + len(name) + sum(map(ord, name)))
    r = dia / 2
    w, h, half_pitch, feed_sign, _, (body_l, body_w) = BOOSTERS[name]
    board = pcbnew.BOARD()
    board.SetCopperLayerCount(2)
    tb = board.GetTitleBlock()
    tb.SetTitle(f"HW.33 RF mock-up axis 3 — {name} on a Ø{dia} ground")
    tb.SetCompany("SilkenNet")
    tb.SetRevision("1")
    tb.SetDate("2026-10-12")
    ds = board.GetDesignSettings()
    ds.m_MinClearance = mm(CLEARANCE)
    ds.m_TrackMinWidth = mm(0.2)
    ds.SetBoardThickness(mm(1.6))
    nets = {}
    for n in ("GND", "ANT", "N2", "N3"):
        net = pcbnew.NETINFO_ITEM(board, n)
        board.Add(net)
        nets[n] = net

    edge = pcbnew.PCB_SHAPE(board)
    edge.SetShape(pcbnew.SHAPE_T_CIRCLE)
    edge.SetCenter(pt(0, 0))
    edge.SetEnd(pt(r, 0))
    edge.SetLayer(pcbnew.Edge_Cuts)
    edge.SetWidth(mm(0.1))
    board.Add(edge)

    # The booster as close to the edge as the margin allows: the outer corners of its pads or of its body — whichever
    # reaches further — on the circle r − EDGE_MARGIN.
    ex, ey = max(half_pitch + w / 2, body_l / 2), max(h / 2, body_w / 2)
    yc = -math.sqrt((r - EDGE_MARGIN) ** 2 - ex ** 2) + ey
    feed, source = booster_footprint(board, name, (0.0, yc), nets["ANT"])
    yg = yc + h / 2 + GAP_TO_GROUND
    # the clearance segment: the arc above y = yg on a circle a little past the outline (so the pour cannot leak round
    # it), closed by the chord at exactly y = yg; with y down, the arc from the left chord end to the right one through
    # angle −π/2 is the top of the board
    rr = r + 0.3
    left = math.atan2(yg, -math.sqrt(rr * rr - yg * yg))
    right = math.atan2(yg, math.sqrt(rr * rr - yg * yg))
    if not left < -math.pi / 2 < right:
        raise SystemExit(f"{name} Ø{dia}: the ground edge y {yg:.2f} does not leave a top segment")
    arc = circle_points(rr, left, right)
    keepout(board, [*arc, arc[0]])
    disc = circle_points(r)
    gnd_zones = [zone(board, layer, disc, nets["GND"]) for layer in (pcbnew.F_Cu, pcbnew.B_Cu)]

    # The line: straight down from the feed pad into the ground area, then the chain.
    start = (feed[0], yg + FEED_DROP)
    if CHAIN_DIRECTION[name] == "across":
        d, side = (-feed_sign, 0.0), (0.0, 1.0)            # towards the centre; shunts go down
    else:
        d, side = (0.0, 1.0), (-feed_sign, 0.0)            # downwards; shunts go towards the centre
    if CHAIN_DIRECTION[name] == "down":
        # the drop enters the ground, steps 1 mm towards the centre (the narrow booster sits so close to the edge that a
        # chain straight under its feed pad pushes the U.FL out of the contour), and the chain continues downwards
        corner = (feed[0], yg + 0.6)
        start = (feed[0] - feed_sign * 1.0, yg + 0.6)
        track(board, feed, corner, nets["ANT"])
        track(board, corner, start, nets["ANT"])
    else:
        track(board, feed, start, nets["ANT"])

    def along(s: float) -> tuple:
        return (start[0] + d[0] * s, start[1] + d[1] * s)

    shunt_off = 1.55                                        # 0603 pad pitch (L_0603_1608Metric pads at ±0.775)
    # the first node: one step clear of the corner where the line turns, or — with no corner — right where it enters
    # the ground (the narrow booster's vertical chain needs that 0.7 mm to keep the U.FL inside the contour)
    s0 = 1.0 if CHAIN_DIRECTION[name] == "across" else 0.3
    node_a, node_c = along(s0), along(s0 + 2 * STEP)
    a = library_footprint(board, "Inductor_SMD", "L_0603_1608Metric", "A", "DNP shunt",
                          (node_a[0] + side[0] * shunt_off / 2, node_a[1] + side[1] * shunt_off / 2), node_a,
                          {"1": nets["ANT"], "2": nets["GND"]})
    b_at = along(s0 + STEP)
    b = library_footprint(board, "Inductor_SMD", "L_0603_1608Metric", "B", "DNP series", b_at, along(s0),
                          {"1": nets["ANT"], "2": nets["N2"]})
    c = library_footprint(board, "Inductor_SMD", "L_0603_1608Metric", "C", "DNP shunt",
                          (node_c[0] + side[0] * shunt_off / 2, node_c[1] + side[1] * shunt_off / 2), node_c,
                          {"1": nets["N2"], "2": nets["GND"]})
    d_at = along(s0 + 3 * STEP)
    dd = library_footprint(board, "Resistor_SMD", "R_0603_1608Metric", "D", "0R series", d_at, along(s0 + 2 * STEP),
                           {"1": nets["N2"], "2": nets["N3"]})
    sig = along(s0 + 4 * STEP + 0.4)                    # + the U.FL courtyard reaching back past its signal pad
    ufl_at = (sig[0] + d[0] * 1.525, sig[1] + d[1] * 1.525)
    j = library_footprint(board, "Connector_Coaxial", "U.FL_Hirose_U.FL-R-SMT-1_Vertical", "J1", "U.FL-R-SMT-1",
                          ufl_at, sig, {"1": nets["N3"], "2": nets["GND"]})
    parts = [a, b, c, dd, j]

    # The line between the sites, on the net of each stretch.
    track(board, start, pad_at(a, "1"), nets["ANT"])
    track(board, pad_at(a, "1"), pad_at(b, "1"), nets["ANT"])
    track(board, pad_at(b, "2"), pad_at(c, "1"), nets["N2"])
    track(board, pad_at(c, "1"), pad_at(dd, "1"), nets["N2"])
    # the U.FL keeps copper out from under its body (its own keepout from x −0.99 local): the line stops short of the
    # signal pad's centre so that its round end stays on the pad
    sig_end = (sig[0] - d[0] * 0.3, sig[1] - d[1] * 0.3)
    track(board, pad_at(dd, "2"), sig_end, nets["N3"])

    # Fit: every pad of every part inside the margin, every part below the clearance line.
    for fp in parts + [f for f in board.GetFootprints() if f.GetReference() == "AE1"]:
        for p in fp.Pads():
            bb = p.GetBoundingBox()
            for cx, cy in ((bb.GetLeft(), bb.GetTop()), (bb.GetRight(), bb.GetTop()),
                           (bb.GetLeft(), bb.GetBottom()), (bb.GetRight(), bb.GetBottom())):
                x, y = pcbnew.ToMM(cx), pcbnew.ToMM(cy)
                if math.hypot(x, y) > r - EDGE_MARGIN + 1e-6:
                    raise SystemExit(f"{name} Ø{dia}: pad {fp.GetReference()}.{p.GetNumber()} leaves the contour "
                                     f"(corner {x:.2f}, {y:.2f} at radius {math.hypot(x, y):.2f} > {r - EDGE_MARGIN:.2f})")
        if fp.GetReference() != "AE1" and pcbnew.ToMM(fp.GetBoundingBox(False).GetTop()) < yg:
            raise SystemExit(f"{name} Ø{dia}: {fp.GetReference()} reaches into the clearance area")
    for x, y in ((sx * body_l / 2, yc + sy * body_w / 2) for sx in (-1, 1) for sy in (-1, 1)):
        if math.hypot(x, y) > r - EDGE_MARGIN + 1e-6:
            raise SystemExit(f"{name} Ø{dia}: the booster body leaves the contour (corner {x:.2f}, {y:.2f})")

    # Stitching: a grid of vias over the ground, kept off every part's courtyard (no via in a soldered pad, none under
    # the U.FL's own keepout), off every track, off the label, and off each other.
    obstacles = []                                        # (kind, …, owner) — a courtyard can be waived for its own part
    for fp in board.GetFootprints():
        bb = fp.GetBoundingBox(False)
        obstacles.append(("box", pcbnew.ToMM(bb.GetLeft()), pcbnew.ToMM(bb.GetTop()),
                          pcbnew.ToMM(bb.GetRight()), pcbnew.ToMM(bb.GetBottom()), fp.GetReference()))
        for p in fp.Pads():                               # …but never a pad, its own ground pad included
            pb = p.GetBoundingBox()
            obstacles.append(("box", pcbnew.ToMM(pb.GetLeft()), pcbnew.ToMM(pb.GetTop()),
                              pcbnew.ToMM(pb.GetRight()), pcbnew.ToMM(pb.GetBottom()), "pad"))
    chain = list(board.GetTracks())
    for t in chain:
        obstacles.append(("seg", *xy(t.GetStart()), *xy(t.GetEnd()), pcbnew.ToMM(t.GetWidth()) / 2, "track"))
    # the label goes on the back, by the bottom edge, short enough for the chord there (KiCad's stroke font ≈ one
    # character height per character)
    label = f"{name[-3:]} D{dia:.2f}"
    label_at = (0.0, r - 2.0)
    half_w = 0.85 * len(label) / 2 + 0.3
    obstacles.append(("box", -half_w, label_at[1] - 0.8, half_w, label_at[1] + 0.8, "label"))
    keep = VIA[0] / 2 + GAP + 0.15
    placed = []

    def clear(x: float, y: float, waive: frozenset = frozenset()) -> bool:
        for o in obstacles:
            if o[-1] in waive:
                continue
            if o[0] == "box":
                dx = max(o[1] - x, 0, x - o[3])
                dy = max(o[2] - y, 0, y - o[4])
                if math.hypot(dx, dy) < keep:
                    return False
            else:
                _, x1, y1, x2, y2, half, _owner = o
                vx, vy = x2 - x1, y2 - y1
                L2 = vx * vx + vy * vy
                u = 0 if L2 == 0 else max(0, min(1, ((x - x1) * vx + (y - y1) * vy) / L2))
                if math.hypot(x - x1 - u * vx, y - y1 - u * vy) < half + keep:
                    return False
        return all(math.dist((x, y), q) >= VIA[0] + 0.3 for q in placed)

    def try_via(x: float, y: float, waive: frozenset = frozenset()) -> bool:
        if y > yg + 0.8 and math.hypot(x, y) < r - 1.0 and clear(x, y, waive):
            placed.append((x, y))
            return True
        return False

    # first one beside each ground pad of the chain, so a shunt's return does not wait for the grid …
    for fp in (a, c, j):
        for p in fp.Pads():
            if p.GetNetname() == "GND":
                px, py = xy(p.GetPosition())
                offsets = [(side[0] * k, side[1] * k) for k in (1.2, 1.4, 1.6, 1.8, 2.0, 2.2)]
                offsets += [(dx * k, dy * k) for k in (1.2, 1.4, 1.6, 1.8, 2.0, 2.2) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                for ox, oy in offsets:
                    if try_via(px + ox, py + oy, waive=frozenset({fp.GetReference()})):
                        break
    # … then a fence along both sides of the coplanar line …
    fence = TRACK / 2 + GAP + VIA[0] / 2 + 0.15
    for t in chain:
        (x1, y1), (x2, y2) = xy(t.GetStart()), xy(t.GetEnd())
        length = math.hypot(x2 - x1, y2 - y1)
        if length < 1e-6:
            continue
        nx, ny = -(y2 - y1) / length, (x2 - x1) / length
        for m in range(int(length / 1.6) + 1):
            u = min(1.0, (m * 1.6 + 0.4) / length)
            for sgn in (1, -1):
                # a fence via may stand inside a chain part's courtyard (beside a series part's body), never on a pad
                try_via(x1 + u * (x2 - x1) + sgn * nx * fence, y1 + u * (y2 - y1) + sgn * ny * fence,
                        waive=frozenset({"A", "B", "C", "D"}))
    # … then the grid
    n = int(r / VIA_PITCH) + 1
    for i in range(-n, n + 1):
        for k in range(-n, n + 1):
            try_via(i * VIA_PITCH, k * VIA_PITCH)
    text(board, label, label_at)
    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    # A via the pour reaches on one layer only stitches nothing, so a candidate is placed only where the pour — filled
    # once without vias — already covers it on BOTH layers; then the pour is filled again around the vias. (Placing all
    # and removing the stray ones crashed KiCad's Python: a removed item's wrapper frees what the board still holds.)
    for x, y in placed:
        if all(z.GetFilledPolysList(z.GetLayer()).Contains(pt(x, y)) for z in gnd_zones):
            via(board, (x, y), nets["GND"])
    filler.Fill(board.Zones())
    depth = r + yg                                                  # segment height from the top of the disc
    segment = r * r * math.acos((r - depth) / r) - (r - depth) * math.sqrt(2 * r * depth - depth * depth)
    return board, {"booster": name, "diameter_mm": dia, "booster_centre_y_mm": round(yc, 3),
                   "clearance_mm2": round(segment, 1), "clearance_share": round(segment / (math.pi * r * r), 3),
                   "ground_edge_y_mm": round(yg, 3), "footprint_source": source, "chain": CHAIN_DIRECTION[name]}


def write_project(path: Path) -> None:
    """The rules KiCad's DRC reads live in the project, not in the board — written here so that a fresh checkout judges
    the board against the same clearances it was built for."""
    path.write_text(json.dumps({
        "board": {"design_settings": {"rules": {
            "min_clearance": CLEARANCE, "min_track_width": 0.2, "min_copper_edge_clearance": 0.3,
            "min_through_hole_diameter": 0.3, "min_hole_to_hole": 0.25, "min_via_annular_width": 0.13,
            "solder_mask_to_copper_clearance": 0.0},
            # the booster is defined here, not in a library, and the library parts carry the board's own net names —
            # «library not configured / mismatch» describes the design's choice, not a defect
            "rule_severities": {"lib_footprint_issues": "ignore", "lib_footprint_mismatch": "ignore"}}},
        "meta": {"filename": path.name, "version": 3},
        "net_settings": {"classes": [{"name": "Default", "clearance": CLEARANCE, "track_width": TRACK,
                                      "via_diameter": VIA[0], "via_drill": VIA[1]}], "meta": {"version": 4}},
    }, indent=2) + "\n")


def run(*args: str) -> None:
    subprocess.run([str(KICAD / "MacOS/kicad-cli"), *args], check=True, capture_output=True, text=True)


def drc_gate(board_file: Path, fab: Path) -> None:
    """Any DRC violation or unconnected item fails the build — no board is written out for fabrication on a hope."""
    report = fab / "drc.json"
    run("pcb", "drc", "--format", "json", "--units", "mm", "--severity-all", "--output", str(report), str(board_file))
    data = json.loads(report.read_text())
    bad = data.get("violations", []) + data.get("unconnected_items", [])
    if bad:
        raise SystemExit(f"DRC failed for {board_file.name}:\n  " +
                         "\n  ".join(f"{v['severity']} {v['type']}: {v['description']}" for v in bad))
    report.unlink()


def fabrication(board_file: Path, fab: Path, stem: str, meta: dict) -> None:
    """Gerbers + drill (zipped for upload) and a bill of materials for hand assembly — every matching site is DNP until
    the VNA names its value, so there is nothing for a PCBA house to place."""
    gerbers = fab / "gerbers"
    gerbers.mkdir(parents=True, exist_ok=True)
    for old in gerbers.iterdir():
        old.unlink()
    run("pcb", "export", "gerbers", "--no-x2", "--layers",
        "F.Cu,B.Cu,F.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts", "--output", f"{gerbers}/", str(board_file))
    run("pcb", "export", "drill", "--format", "excellon", "--output", f"{gerbers}/", str(board_file))
    with zipfile.ZipFile(fab / f"{stem}_gerbers.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(gerbers.iterdir()):
            z.write(f, f.name)
    with (fab / f"{stem}_bom.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(("Designator", "Footprint", "Part", "Fit"))
        w.writerow(("AE1", f"Ignion {meta['booster']} ({meta['footprint_source']})", f"Ignion {meta['booster']}", "fit"))
        w.writerow(("J1", "U.FL_Hirose_U.FL-R-SMT-1_Vertical", "Hirose U.FL-R-SMT-1", "fit"))
        w.writerow(("A", "L_0603_1608Metric", "shunt — value from the VNA", "DNP"))
        w.writerow(("B", "L_0603_1608Metric", "series — value from the VNA", "DNP"))
        w.writerow(("C", "L_0603_1608Metric", "shunt — value from the VNA", "DNP"))
        w.writerow(("D", "R_0603_1608Metric", "0 Ω until a T is needed", "fit"))


def main() -> int:
    for name in BOOSTERS:
        for dia in DIAMETERS:
            stem = f"hw33_axis3_{name.lower().replace('-', '')}_d{str(dia).replace('.', 'p')}"
            board, meta = build(name, dia)
            board_file = HERE / f"{stem}.kicad_pcb"
            board.Save(str(board_file))
            write_project(HERE / f"{stem}.kicad_pro")
            fab = HERE / "fab" / stem
            fab.mkdir(parents=True, exist_ok=True)
            try:
                drc_gate(board_file, fab)
            except SystemExit:
                board_file.unlink()                                 # a board that failed DRC is not left in the tree
                (HERE / f"{stem}.kicad_pro").unlink()
                raise
            fabrication(board_file, fab, stem, meta)
            print(f"wrote {stem} — booster centre y {meta['booster_centre_y_mm']}, ground edge y "
                  f"{meta['ground_edge_y_mm']} mm, clearance segment {meta['clearance_mm2']} mm² = "
                  f"{meta['clearance_share']:.0%} of the disc (chain {meta['chain']}; DRC clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
