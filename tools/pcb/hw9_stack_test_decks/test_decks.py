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
    # the upper deck's name — a box about the size KiCad draws four letters at 0.8 mm — finds room (the build holds KiCad's box)
    lx, ly = decks.label_at()
    assert decks.clear_of_supports(lx - 1.8, ly - 0.75, lx + 1.8, ly + 0.75)
    assert not decks.clear_of_supports(*decks.STANDOFFS[0], *decks.STANDOFFS[0])         # and the check can say no


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
