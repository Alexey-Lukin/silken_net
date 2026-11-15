# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.9 — land patterns of the board-to-board pair of the bench stack's test decks (00_07 HW.9, ⚖️ founder 2026-11-15;
the pair — 02_01 §3.1 pos. 12): the Samtec FW-SM header and the Samtec CLP-SM socket, 5 positions x 2 rows (ordering codes: 02_01 §3.1 pos. 12), both
without the –A option. KiCad ships neither, so they are drawn here from the vendor's drawings.

Sources (Samtec, fetched 2026-11-15 from suddendocs.samtec.com/prints/; the PDFs are the vendor's and are NOT kept in the
tree — the numbers below are their transcription, each with the sheet and view it was read on):
  S1  clp-1xx-xx-xxx-d-xx-footprint.pdf      «RECOMMENDED PCB LAYOUT FOR CLP-1XX-XX-XXX-D-XX», REVISION W (10/2/2023,
                                             ECN-467634), 6 sheets, sha256 b8481e225d203e24…; has a text layer
  S2  clp-1xx-xx-xxx-d-xx-xx-xx-mkt.pdf      print CLP-1XX-XX-XXX-D-XX-XX-XX, REVISION DH, 3 sheets, sha256 43dcb7b9ba31183c…
  S3  fw-d-sm-1-footprint.pdf                «RECOMMENDED PCB LAYOUT FOR DOUBLE ROW FW-XX-XX-XX-D-XX», REV. D, 1 sheet,
                                             sha256 0b7e8f90162e42b9…; NO text layer — read off a 250 dpi raster
  S4  fw-d-sm-2-footprint.pdf                the double-row FW stencil sheet (drawn on the four-position part), REV. D, 1 sheet,
                                             sha256 1b0052e3c5037abc…; no text layer; no constant below comes from it
  S5 fw-xx-xx-xx-d-xxx-xxx-xx-x-xx-mkt.pdf  print FW-XX-XX-XX-D-XXX-XXX-XX-X-XX, REVISION DG, 4 sheets, sha256 52a12dde4d8157ef…

Every constant is the drawing's own INCH value (the prints say «DIMENSIONS ARE IN INCHES»). The bracketed mm beside it is
the vendor's conversion of that same number, so test_footprints.py, which holds each constant to it, catches a slip of
transcription — not a misreading of the drawing. «read» = printed in the drawing; «derived» = our arithmetic on read
numbers — the pad centre (span − pad length) / 2, the per-N lengths, post_gap(), post_channel(); «interpreted» = a
reading the drawing does not settle. Neither footprint drawing carries a tolerance, a courtyard or a mask rule.

Numbering. The frame of pads() is KiCad's footprint frame: the part seen from its own component side, x to the right,
y DOWN.
  • FW — read (S3 FIG 1, the board seen from the header's side): «02» above the top row and «01» below the bottom row at
    the LEFT end, «03» next to «01». S5 sheet 1, top view (posts towards the reader), agrees: 02…50 / 01…49 left to right.
  • CLP — CHOSEN as the mirror of the header's, so that with the socket on the BOTTOM of the upper board
    (connector_footprint(…, bottom=True), mirrored left–right) socket pad n lies over header pad n. «Post n enters
    cavity n» is then true by construction: the cavity's number is ours.
    What the vendor gives: S1 numbers no pad; S2 sheet 1, top view (the entry face, cavities towards the reader), prints
    «02» by the top row and «01» by the bottom row, past the RIGHT end of the body, with no leader to a contact. The rows
    are read; the end is interpreted. If the labels mark that end, our numbering is Samtec's. If they only name the rows
    and Samtec's 01 sits at the left end, the ends are swapped — our 1…10 are their 9, 10, 7, 8, 5, 6, 3, 4, 1, 2 — and
    the rows stay. That matters only where this footprint meets someone else's footprint or symbol of one of the halves:
    no print shows a pin-1 mark on either body, and without –A both are symmetric under a half-turn.
"""
from __future__ import annotations

INCH = 25.4

PARTS = {
    "FW": {
        "value": "FW-SM 2x5",
        "pitch": 0.050,              # read, S3 FIG 1 «.050 [1.27] (TYP)» — pad centres along a row
        "pad_w": 0.029,              # read, S3 FIG 1 «.029 [.74]» — along the row
        "pad_l": 0.110,              # read, S3 FIG 1 «0.110 [2.79] (TYP)» — across the row
        "span": 0.270,               # read, S3 FIG 1 «.270 [6.86]» — outer edge to outer edge of the two rows
        # read, S3 FIG 1 «CONNECTOR OUTLINE (SEE NOTE 2)» «.135 [3.43]» × «NO. OF POS X .050 [1.27]»; note 2: «OTHER
        # COMPONENTS PLACED ON PCB SHALL AVOID THIS ZONE» (S5 sheet 1 gives the body the same .135 [3.43] REF)
        "body_w": 0.135,
        "body_l_over_pitch": 0.0,
        "row_pitch": 0.050,          # read, S5 sheet 1 FIG 1, end view «.050[1.27] REF» — between the two rows of posts
        "pin1_end": -1,              # read, S3 FIG 1 + S5 sheet 1 top view — see «Numbering» above
    },
    "CLP": {
        "value": "CLP-SM 2x5",
        "pitch": 0.050,              # read, S1 sheet 1 FIG 1 «.050[1.27] (TYP)»
        "pad_w": 0.029,              # read, S1 sheet 1 FIG 1 «.029[0.74] (TYP)»
        "pad_l": 0.058,              # read, S1 sheet 1 FIG 1 «.058[1.47] (TYP)»
        "span": 0.185,               # read, S1 sheet 1 FIG 1 «.185[4.70]» (the same in table 1 of sheet 4, row –D)
        # read, S2 sheet 1 top view: «.120[3.05] REF» × «(No OF POS X .0500[1.270]) + .017[0.43]±.008[0.20]». The body,
        # not a zone: for the socket the vendor draws no «avoid» zone
        "body_w": 0.120,
        "body_l_over_pitch": 0.017,
        "row_pitch": 0.050,          # read, S2 sheet 1 SECTION "A"-"A" «.050[1.27] REF» — between the two cavity axes
        "pin1_end": +1,              # interpreted — chosen as the mirror of FW's; see «Numbering» above
    },
}
POST = 0.016                         # read, S5 sheet 1 FIG 1, side view «.016[0.41] SQ REF (TYP)» — the post's section
COURTYARD_MARGIN = 0.25              # mm, OURS (the habit of hw12 / hw33) — no drawing gives a courtyard


def pads(part: str, n: int = 5) -> list:
    """[(number, x, y, w, h)] in mm for n positions per row; odd numbers in the row drawn at the bottom (+y), both
    drawings. Pad centre across the row — derived: (span − pad length) / 2."""
    p = PARTS[part]
    yc = (p["span"] - p["pad_l"]) / 2
    out = []
    for k in range(n):
        x = p["pin1_end"] * ((n - 1) / 2 - k) * p["pitch"]
        for number, y in ((2 * k + 1, yc), (2 * k + 2, -yc)):
            out.append((str(number), x * INCH, y * INCH, p["pad_w"] * INCH, p["pad_l"] * INCH))
    return out


def body(part: str, n: int = 5) -> tuple:
    """(length along the rows, width) in mm — for FW the vendor's «other components shall avoid» zone."""
    p = PARTS[part]
    return (n * p["pitch"] + p["body_l_over_pitch"]) * INCH, p["body_w"] * INCH


def post_gap() -> tuple:
    """(inner edge of a CLP pad, outer face of a post, the gap between them) in mm from the pair's centreline, in plan,
    nominal — derived: span / 2 − pad length (S1) against row pitch / 2 + post / 2 (S5; both REF)."""
    clp, fw = PARTS["CLP"], PARTS["FW"]
    pad_inner = clp["span"] / 2 - clp["pad_l"]
    post_face = fw["row_pitch"] / 2 + POST / 2
    return pad_inner * INCH, post_face * INCH, (pad_inner - post_face) * INCH


def post_channel() -> float:
    """The strip between the inner faces of the two rows of posts, mm, in plan, nominal — derived: row pitch − post
    (S5; both REF)."""
    return (PARTS["FW"]["row_pitch"] - POST) * INCH


def connector_footprint(board, part: str, ref: str, at: tuple, bottom: bool = False):
    """Draw the land pattern into the board at `at` (mm). bottom=True puts it on the back, mirrored left–right — the
    socket under the upper deck. Pads are copper + mask + paste 1 : 1 — the vendor's stencil sheets (S1 sheet 4; S4)
    draw the apertures «same as FIG 1»."""
    import pcbnew  # here, not at the top: the geometry above and its test run without KiCad

    def pt(x: float, y: float):
        return pcbnew.VECTOR2I(pcbnew.FromMM(at[0] + x), pcbnew.FromMM(at[1] + y))

    n = 5
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("SilkenNet", f"Samtec_{PARTS[part]['value']}"))
    fp.SetReference(ref)
    fp.SetValue(PARTS[part]["value"])
    fp.SetAttributes(pcbnew.FP_SMD)
    fp.SetPosition(pt(0, 0))
    for number, x, y, w, h in pads(part, n):
        pad = pcbnew.PAD(fp)
        pad.SetNumber(number)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
        pad.SetShape(pcbnew.F_Cu, pcbnew.PAD_SHAPE_RECT)
        pad.SetSize(pcbnew.F_Cu, pcbnew.VECTOR2I(pcbnew.FromMM(w), pcbnew.FromMM(h)))
        pad.SetLayerSet(pad.SMDMask())
        pad.SetPosition(pt(x, y))
        fp.Add(pad)
    body_l, body_w = body(part, n)
    ex = max(body_l / 2, max(abs(x) + w / 2 for _, x, _y, w, _h in pads(part, n)))    # pads or body, whichever
    ey = max(body_w / 2, max(abs(y) + h / 2 for _, _x, y, _w, h in pads(part, n)))    # reaches further
    for layer, hx, hy, width in ((pcbnew.F_CrtYd, ex + COURTYARD_MARGIN, ey + COURTYARD_MARGIN, 0.05),
                                 (pcbnew.F_Fab, body_l / 2, body_w / 2, 0.10)):
        corners = ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))
        for i in range(4):   # no zip(strict=) — KiCad's Python is 3.9
            shape = pcbnew.PCB_SHAPE(fp)
            shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
            shape.SetStart(pt(*corners[i]))
            shape.SetEnd(pt(*corners[(i + 1) % 4]))
            shape.SetLayer(layer)
            shape.SetWidth(pcbnew.FromMM(width))
            fp.Add(shape)
    fp.Reference().SetVisible(False)
    fp.Value().SetVisible(False)
    board.Add(fp)
    if bottom:
        fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    return fp
