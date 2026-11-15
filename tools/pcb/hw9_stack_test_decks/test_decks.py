# SPDX-License-Identifier: AGPL-3.0-or-later
"""The standoff's land pattern and the geometry of the two test decks — no KiCad needed:

    python3 -m pytest tools/pcb/hw9_stack_test_decks

What each check is held to: the standoff — to the tree's EARLIER reading of the same datasheet (deck_standoff_shortlist,
2026-10-05; ours is of 2026-11-15) and to the stencil's own arithmetic; the arrangement and the courtyards — to the node:
the canon's margin and the node's searcher itself (Ruby; skipped where there is none); the threshold — to the canon's
formula and example, read out of 02_01; the surfaces — to the parameter that names them."""
import math
import re
import shutil
from pathlib import Path

import decks
import footprints
import pytest

ROOT = Path(__file__).resolve().parents[3]
S = footprints.STANDOFF
needs_ruby = pytest.mark.skipif(shutil.which("ruby") is None, reason="the node's searcher is Ruby")


def area(polygon):
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(polygon, polygon[1:] + polygon[:1], strict=True))) / 2


def quadrant_area(r, half):
    """{x ≥ half, y ≥ half, x² + y² ≤ r²}, in closed form — the test's own integral, not the polygon's arithmetic."""
    c = math.sqrt(r * r - half * half)

    def primitive(x):
        return x / 2 * math.sqrt(r * r - x * x) + r * r / 2 * math.asin(x / r)

    return primitive(c) - primitive(half) - half * (c - half)


def disc_rect_gap(centre, r, rect_centre, hx, hy):
    dx, dy = abs(centre[0] - rect_centre[0]) - hx, abs(centre[1] - rect_centre[1]) - hy
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - r


def surface(shapes, x, y):
    """(copper, mask opened) at a point of the upper deck's back, from upper_surfaces() alone."""
    def inside(kind, n):
        return math.hypot(x - n[0], y - n[1]) <= n[2] if kind == "circle" else n[0] <= x <= n[2] and n[1] <= y <= n[3]

    return tuple(any(layer == want and inside(kind, n) for layer, kind, n in shapes) for want in ("Cu", "Mask"))


def test_standoff_numbers_match_the_trees_earlier_reading_of_the_datasheet():
    sheet = (ROOT / "docs/protocols/hardware/deck_standoff_shortlist.md").read_text(encoding="utf-8")
    row = next(line for line in sheet.splitlines() if line.startswith("| `9774080243R` |"))
    # | P/N | M2 × L ±tol | body | spigot Ø × length | pad / NPTH | …
    assert [float(v) for v in re.findall(r"\d+\.\d+", row.split("≤")[0])] == [
        S["length"], S["length_tol"], S["body_d"], S["spigot_d"], S["spigot_l"], S["pad_d"], S["hole_d"]]
    stencil = re.search(r"кільце Ø([\d.]+) / Ø([\d.]+) на чотири сектори з містками ([\d.]+), товщина пасти \(трафарету\) ≥ (\d+) мкм", sheet)
    assert [float(v) for v in stencil.groups()] == [S["paste_od"], S["paste_id"], S["paste_bridge"], S["paste_min"] * 1000]
    # the drawing's own order of things: spigot in the hole, the paste ring inside the pad and off the hole, the body on the pad
    assert S["spigot_d"] < S["hole_d"] < S["paste_id"] < S["body_d"] < S["paste_od"] < S["pad_d"]


def test_standoff_paste_is_the_stencil_the_datasheet_draws():
    apertures = footprints.standoff_paste()
    ro, ri, half = S["paste_od"] / 2, S["paste_id"] / 2, S["paste_bridge"] / 2
    assert len(apertures) == 4
    radii = [math.hypot(x, y) for a in apertures for x, y in a]
    assert min(radii) == pytest.approx(ri) and max(radii) == pytest.approx(ro)
    assert min(min(abs(x), abs(y)) for a in apertures for x, y in a) == pytest.approx(half)        # the 0.6 bridges
    assert {(x > 0, y > 0) for a in apertures for x, y in a} == {(True, True), (True, False), (False, True), (False, False)}
    # chords inside the arcs lose a little; a ring 0.04 mm short on the radius — KiCad's own footprint — loses 5.7 %
    assert sum(map(area, apertures)) == pytest.approx(4 * (quadrant_area(ro, half) - quadrant_area(ri, half)), rel=2e-3)


@needs_ruby
def test_courtyards_are_the_ones_the_nodes_searcher_lays_out():
    node = decks.node_layout()
    assert [2 * v for v in footprints.courtyard("FW")] == pytest.approx(node["header"], abs=0.006)
    assert [2 * v for v in footprints.courtyard("CLP")] == pytest.approx(node["socket"], abs=0.006)
    assert S["pad_d"] + 2 * footprints.COURTYARD_MARGIN == pytest.approx(node["pad_courtyard_d"])
    assert S["body_d"] == pytest.approx(node["face_d"])


def test_arrangement_keeps_the_margin_the_canon_prints_for_the_node():
    """02_01 §3.1, the inset of pos. 25: on the package target conditions (1)–(2) «лягають без ціни — +0.59 мм», bound by
    the top of the Power Deck — the standoffs' pads against the header. The decks stand at that margin (to the rounding
    of the searcher's 0.03 mm and 0.6°), the standoffs on one line with the pair midway and its rows along it."""
    assert [y for _, y in decks.STANDOFFS] == [0.0, 0.0] and decks.STANDOFFS[0][0] == -decks.STANDOFFS[1][0]
    assert decks.PAIR[0] == 0.0
    gaps = [disc_rect_gap(at, S["pad_d"] / 2 + footprints.COURTYARD_MARGIN, decks.PAIR, *footprints.courtyard("FW"))
            for at in decks.STANDOFFS]
    assert gaps == pytest.approx([0.59, 0.59], abs=0.03)
    # the bottom of the RF Deck is looser there, as in the node: the end faces' courtyards against the socket
    assert min(disc_rect_gap(at, S["body_d"] / 2 + footprints.COURTYARD_MARGIN, decks.PAIR, *footprints.courtyard("CLP"))
               for at in decks.STANDOFFS) > 0.59


@needs_ruby
def test_arrangement_is_the_layout_the_nodes_searcher_finds():
    node = decks.node_layout()
    assert node["span"] == pytest.approx(decks.SPAN, abs=0.005)
    assert node["pair"][1] == pytest.approx(decks.PAIR_OFFSET, abs=0.005)
    assert abs(node["pair"][0]) < 0.05 and node["angle"] < 1.0          # what the decks round to «midway» and «parallel»
    # condition (1) of the inset of pos. 25: the bead's resultant lies in the strip of the end faces — and here it does
    # so by a standoff, off the board's middle, which is why the decks print where it is
    assert abs(node["G"][1]) < S["body_d"] / 2 and abs(abs(node["G"][0]) - decks.SPAN / 2) < S["body_d"] / 2


def test_contour_is_the_smallest_round_both_decks_and_keyed():
    contour = decks.outline()
    xs, ys = [x for x, _ in contour], [y for _, y in contour]
    fw, clp = footprints.courtyard("FW"), footprints.courtyard("CLP")
    r = S["pad_d"] / 2 + footprints.COURTYARD_MARGIN
    assert max(xs) - decks.STANDOFFS[1][0] - r == pytest.approx(decks.EDGE_FIELD)        # each side stands EDGE_FIELD
    assert decks.STANDOFFS[0][0] - r - min(xs) == pytest.approx(decks.EDGE_FIELD)        # off the courtyard nearest to it
    assert -r - min(ys) == pytest.approx(decks.EDGE_FIELD)
    assert max(ys) - decks.PAIR[1] - max(fw[1], clp[1]) == pytest.approx(decks.EDGE_FIELD)
    assert max(fw[0], clp[0]) < decks.STANDOFFS[1][0] and r >= decks.LANDING_D / 2
    # the cut corner costs no field: its edge stays further from the standoff beside it than the straight sides do
    (ax, ay), (bx, by) = contour[4], contour[0]
    sx, sy = decks.STANDOFFS[0]
    cut = abs((bx - ax) * (ay - sy) - (ax - sx) * (by - ay)) / math.hypot(bx - ax, by - ay)
    assert cut - r >= decks.EDGE_FIELD
    # the key: turned half round — about the pair, as a reversed mate would be, or about the standoffs' middle — the
    # contour does not fall onto itself, and with the pair ON the standoffs' line the cut corner alone still says so
    for cx, cy in (decks.PAIR, (0.0, 0.0)):
        assert {(round(2 * cx - x, 6), round(2 * cy - y, 6)) for x, y in contour} != {(round(x, 6), round(y, 6)) for x, y in contour}
    assert len(contour) == 5 and decks.KEY > 0
    # print finds room off every probed surface — boxes about the size KiCad draws four letters at 0.8 mm (the build holds
    # KiCad's own boxes, and the Gerbers of the base faces empty); and the check can say no
    for x, y in decks.print_spots().values():
        assert decks.clear_of_supports(x - 1.8, y - 0.75, x + 1.8, y + 0.75)
    assert decks.KEEP_R >= decks.LANDING_D / 2 + decks.MASK_RELIEF
    assert not decks.clear_of_supports(*decks.STANDOFFS[0], *decks.STANDOFFS[0])


@pytest.mark.parametrize("face", decks.SURFACES)
@pytest.mark.parametrize("holes", decks.SURFACES)
def test_surfaces_put_copper_and_mask_where_the_parameter_says(face, holes):
    shapes = decks.upper_surfaces(face, holes)
    r = S["body_d"] / 2
    for cx, cy in decks.STANDOFFS:                                          # the whole end face, rim included
        for k in range(16):
            assert surface(shapes, cx + r * math.cos(k * math.pi / 8), cy + r * math.sin(k * math.pi / 8)) == decks.SURFACES[face]
        assert surface(shapes, cx, cy) == decks.SURFACES[face]
        # past the copper and inside the relief the mask stays as opened as under the face — a shifted mask meets no copper
        assert surface(shapes, cx + decks.LANDING_D / 2 + decks.MASK_RELIEF / 2, cy) == (False, decks.SURFACES[face][1])
    copper, opened = decks.SURFACES[holes]
    pad_inner, post_face, _ = footprints.post_gap()
    row = footprints.PARTS["FW"]["row_pitch"] / 2 * footprints.INCH
    for _number, x, y, _w, h in footprints.pads("CLP"):
        side = math.copysign(1, y)
        assert surface(shapes, x, decks.PAIR[1] + side * row) == (copper, opened)                    # a post's axis
        assert surface(shapes, x, decks.PAIR[1] + side * post_face) == (False, opened)               # its outer face
        assert surface(shapes, x, decks.PAIR[1] + y) == (False, False)                               # the pad is the pad's
        if copper:                                                          # the island keeps the rule off the pads
            island = next(n for layer, kind, n in shapes if (layer, kind) == ("Cu", "rect"))
            assert abs(y) - h / 2 - (island[3] - decks.PAIR[1]) == pytest.approx(decks.CLEARANCE)
    assert pad_inner - post_face == pytest.approx(0.0381, abs=1e-4)
    assert surface(shapes, 0.0, -2.0) == (False, False)                     # nothing at a point away from all of them


@needs_ruby
def test_points_are_the_bench_sheets():
    """deck_stack_gap_bench_sheet.md §2.1, §4, §9 p. 2 — names, and where each stands on the geometry it names."""
    node = decks.node_layout()
    at = {name: (x, y) for name, _deck, _face, x, y in decks.points(node)}
    deck = {name: d for name, d, *_ in decks.points(node)}
    assert {"P_H1", "P_H2", "P_1", "P_2", "P_A", "P_B", "G", "Z_padH1", "Z_padH2", "Z_padF", "Z_A1", "Z_A2", "Z_disc.H1",
            "Z_disc.H2", "Z_strip", "Z_pad.1", "Z_pad.2", "Z_E1", "Z_E2", *(f"Z_H{i}.{k}" for i in (1, 2) for k in (1, 2, 3))} == set(at)
    assert {deck[n] for n in at if n.startswith("P_") or n == "G"} == {"stack"} and at["G"] == node["G"]
    (h1x, h1y), g = decks.STANDOFFS[0], node["G"]
    # P_H1 on H1's ring, on the side away from G — the line from G through H1's axis; the ring is the shoulder's
    v, w = (at["P_H1"][0] - h1x, at["P_H1"][1] - h1y), (g[0] - h1x, g[1] - h1y)
    assert math.hypot(*v) == pytest.approx(decks.RING_R) and v[0] * w[1] - v[1] * w[0] == pytest.approx(0, abs=1e-9)
    assert v[0] * w[0] + v[1] * w[1] < 0
    assert S["spigot_d"] / 2 < decks.RING_R < S["body_d"] / 2
    # the sheet compares the stack's reading at P_Hi with the deck's at the same point: a ring point and the disc
    for i in (1, 2):
        assert at[f"Z_H{i}.1"] == at[f"Z_disc.H{i}"] == at[f"P_H{i}"]
        ring = [at[f"Z_H{i}.{k}"] for k in (1, 2, 3)]
        cx, cy = decks.STANDOFFS[i - 1]
        assert all(math.hypot(x - cx, y - cy) == pytest.approx(decks.RING_R) for x, y in ring)
        assert [math.dist(a, b) for a, b in ((ring[0], ring[1]), (ring[1], ring[2]), (ring[2], ring[0]))] == pytest.approx([decks.RING_R * math.sqrt(3)] * 3)
        r = math.dist(at[f"Z_padH{i}"], (cx, cy))
        assert S["hole_d"] / 2 < r < S["pad_d"] / 2                                     # on the pad's ring
    assert at["P_H2"] == pytest.approx((-at["P_H1"][0], at["P_H1"][1]))                  # H2: the mirror of H1's side
    # on the pads they name: the header's pad 1; the socket's pad in each row, mirrored onto the back
    _n, x, y, w_, h_ = footprints.pads("FW")[0]
    assert abs(at["Z_padF"][0] - x) < w_ / 2 and abs(at["Z_padF"][1] - decks.PAIR[1] - y) < h_ / 2
    rows = set()
    for name, (_n, x, y, w_, h_) in zip(("Z_pad.1", "Z_pad.2"), footprints.pads("CLP")[:2], strict=True):
        assert abs(at[name][0] + x) < w_ / 2 and abs(at[name][1] - decks.PAIR[1] - y) < h_ / 2
        rows.add(math.copysign(1, y))
    assert rows == {1, -1}
    # the strip under the holes, the bodies' ends clear of the posts, the windows round the pair
    pad_inner = footprints.post_gap()[0]
    assert at["Z_strip"] == decks.PAIR
    column, post = abs(footprints.pads("FW")[0][1]), footprints.POST * footprints.INCH / 2
    for part, ends in (("FW", ("Z_A1", "Z_A2")), ("CLP", ("Z_E1", "Z_E2"))):
        for name, s in zip(ends, (-1, 1), strict=True):
            x, y = at[name]
            assert y == decks.PAIR[1] and s * x > column + post and abs(x) < footprints.body(part)[0] / 2
    assert at["P_1"] == (-column, decks.PAIR[1]) and at["P_2"] == (column, decks.PAIR[1])
    assert at["P_A"][1] < decks.PAIR[1] - pad_inner and at["P_B"][1] > decks.PAIR[1] + pad_inner
    xs, ys = [x for x, _ in decks.outline()], [y for _, y in decks.outline()]
    assert all(min(xs) < x < max(xs) and min(ys) < y < max(ys) for x, y in at.values())


def test_threshold_of_the_written_decks_is_the_canons_example():
    """02_01 §3.1, pos. 12, last ⊕ — the form and the example read out of the canon, not copied: what the decks' names
    spell, through SURFACES, must give the canon's example threshold for that pair of surfaces."""
    canon = (ROOT / "docs/02_01_Hardware_Architecture_and_BOM.md").read_text(encoding="utf-8")
    assert float(re.search(r"Δ\* = \(([\d.]+) − c \+ e \+ s₃\)/2", canon).group(1)) == decks.SWITCH
    m = re.search(r"Приклад при міді ([\d.]+) мм і s₃ = 0: голий склотекстоліт і під торцем, і під отворами — ≈ ([\d.]+) мм; "
                  r"торець на міді, отвори голі — ≈ ([\d.]+) мм", canon)
    assert float(m.group(1)) == decks.COPPER
    assert {"bb": float(m.group(2)), "cb": float(m.group(3))} == decks.CANON_EXAMPLE
    for name in decks.VARIANTS:
        assert decks.threshold(*(decks.SURFACES[s] for s in decks.variant(name))) == pytest.approx(decks.CANON_EXAMPLE[name], abs=6e-4)
    assert decks.variant("bb") == ("bare", "bare") and decks.variant("cb") == ("copper", "bare")
    with pytest.raises(ValueError):                                         # copper under mask: thickness is the order's
        decks.threshold(decks.SURFACES["copper_mask"], decks.SURFACES["bare"])
