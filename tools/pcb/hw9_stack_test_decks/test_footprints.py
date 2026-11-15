# SPDX-License-Identifier: AGPL-3.0-or-later
"""The land patterns of footprints.py against the vendor's drawings — no KiCad needed:

    python3 -m pytest tools/pcb/hw9_stack_test_decks

The constants are the drawings' inch values; the literals below are the same drawings' bracketed millimetres (sheet and
view — in the header of footprints.py). The bracket is the vendor's conversion of the same number, rounded to 0.01 —
hence abs=0.005 — so these checks catch a slip of transcription, not a misreading of the drawing."""
import math
from itertools import pairwise

import footprints
import pytest

N = 5
MM = {"abs": 0.005}


def contact_axes(part):
    """{number: (x, y)} — the axis of the post (FW) or of the cavity (CLP) behind each pad: the pad's column, half the
    row pitch off the centreline on the pad's side."""
    half = footprints.PARTS[part]["row_pitch"] / 2 * footprints.INCH
    return {number: (x, math.copysign(half, y)) for number, x, y, _w, _h in footprints.pads(part, N)}


@pytest.mark.parametrize(("part", "pad_w", "pad_l", "span"), [("FW", 0.74, 2.79, 6.86), ("CLP", 0.74, 1.47, 4.70)])
def test_pads_match_the_footprint_drawing(part, pad_w, pad_l, span):
    pads = footprints.pads(part, N)
    assert sorted(int(number) for number, *_ in pads) == list(range(1, 2 * N + 1))
    xs = sorted({round(x, 6) for _, x, *_ in pads})
    assert len(xs) == N
    assert [b - a for a, b in pairwise(xs)] == pytest.approx([1.27] * (N - 1), **MM)                    # pitch
    assert xs[-1] - xs[0] == pytest.approx(N * 1.27 - 1.27, **MM)          # «NO OF POS x .050[1.27] − .050[1.27]»
    assert all((w, h) == pytest.approx((pad_w, pad_l), **MM) for *_, w, h in pads)
    assert max(y + h / 2 for _, _x, y, _w, h in pads) - min(y - h / 2 for _, _x, y, _w, h in pads) == pytest.approx(span, **MM)
    # «ALL DIMENSIONS ARE SYMMETRIC ABOUT THE CENTERLINE(S)» — the copper, whatever the numbers on it
    copper = {(round(x, 6), round(y, 6)) for _, x, y, *_ in pads}
    assert copper == {(-x, y) for x, y in copper} == {(x, -y) for x, y in copper}


def test_header_numbering_zigzags_from_the_end_the_drawing_marks():
    """FW only: S3 numbers its pads. The socket's footprint drawing numbers none — its numbering is chosen, and the
    mate below is what holds it."""
    at = {number: (x, y) for number, x, y, *_ in footprints.pads("FW", N)}
    assert at["1"][0] == at["2"][0] == pytest.approx(-2 * 1.27, **MM)                 # 01 and 02 share the left end …
    assert at["1"][1] > 0 > at["2"][1]                                                # … 01 below, 02 above (y is down)
    assert at["3"] == pytest.approx((-1.27, at["1"][1]), **MM)                        # 03 next to 01, one pitch inwards
    assert at["10"] == pytest.approx((-at["1"][0], at["2"][1]), **MM)


def test_bodies_match_the_drawings():
    assert footprints.body("FW", N) == pytest.approx((6.35, 3.43), **MM)       # the header's «shall avoid» zone, S3
    assert footprints.body("CLP", N) == pytest.approx((6.78, 3.05), **MM)      # the socket's body, S2


def test_socket_numbering_is_the_mirror_of_the_headers():
    """Code against code: the mirror is written by this test, so it holds the two numberings (and the two row pitches)
    to each other — not KiCad's flip. A wrong flip direction in connector_footprint() passes here; build_demo.py checks
    the flip itself, on the positions KiCad reports."""
    posts, cavities = contact_axes("FW"), contact_axes("CLP")
    assert all(abs(y) == pytest.approx(1.27 / 2, **MM) for _, y in posts.values())    # «.050[1.27] REF» between rows
    mirrored = {number: (-x, y) for number, (x, y) in cavities.items()}       # seen through the board: left ↔ right
    assert mirrored == {number: pytest.approx(axis, abs=1e-9) for number, axis in posts.items()}


def test_gap_between_the_socket_pad_and_the_post_path():
    pad_inner, post_face, gap = footprints.post_gap()
    assert pad_inner == pytest.approx(4.70 / 2 - 1.47, **MM)
    assert post_face == pytest.approx(1.27 / 2 + 0.41 / 2, **MM)
    assert round(gap / footprints.INCH, 4) == 0.0015
    assert round(footprints.post_channel() / footprints.INCH, 4) == 0.034
