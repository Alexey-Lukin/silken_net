# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.9 — the geometry of the two test decks of the bench stack (00_07 HW.9, ⚖️ founder 2026-11-15: «a pair of small boards —
the lower: the header and two standoffs; the upper: the socket»). Pure — no KiCad; build_decks.py draws it, test_decks.py
holds it.

The frame is the stack seen from ABOVE, which is KiCad's canvas of both boards at once (a board is drawn from its front,
and the front of each deck faces up): x along the line through the two standoffs, y down, the origin midway between
them. The lower deck carries the header and the standoffs on its front; the upper deck carries the socket and the
surfaces the standoffs' end faces meet on its BACK, at the same x, y.

What the node gives, and what it does not. The node has no layout yet: tools/firmware/standoff_layout_fit.rb searches
one — the standoffs' pads and the header on the top of the Power Deck, the standoffs' faces, the socket and the EDLC on
the bottom of the RF Deck, under conditions (1)–(2) of 02_01 §3.1, the inset of pos. 25 — and prints its margins, not
its coordinates. node_layout() asks it for them. SPAN and PAIR_OFFSET below are that layout rounded; both the test and
the build hold them to the searcher. One layout of a heuristic search on today's radome.json, not a ruling: the decks are
a proxy, and the root move will shift it.
"""
from __future__ import annotations

import functools
import json
import math
import subprocess
from pathlib import Path

from footprints import COURTYARD_MARGIN, INCH, PARTS, STANDOFF, body, courtyard, pads, post_gap

ROOT = Path(__file__).resolve().parents[3]

# ── the arrangement — the node's, as far as the node has one ────────────────────────────────────────────────────────
SPAN = 13.86            # mm between the standoffs' axes — the searcher's 13.859
PAIR_OFFSET = 3.79      # mm from the standoffs' line to the pair's centre — the searcher's 3.794; the pair sits midway
#                         along the line (the searcher: 0.027 off the middle → 0) with its rows parallel to it (0.63° → 0)
STANDOFFS = ((-SPAN / 2, 0.0), (SPAN / 2, 0.0))
PAIR = (0.0, PAIR_OFFSET)

# ── ours — the node says nothing about any of these ─────────────────────────────────────────────────────────────────
EDGE_FIELD = 1.0        # mm from the outermost courtyard to the board's edge
KEY = 2.0               # mm, the leg of the cut corner — the same corner of both decks in the frame above
LANDING_D = STANDOFF["pad_d"]   # Ø of the surface prepared under an end face: the standoff's own pad, 0.475 mm wider
#                                 than the face all round — room for where the pair and the solder let the deck settle
MASK_RELIEF = 0.5       # mm, the mask's opening under an end face stands this far outside LANDING_D — so a shifted mask
#                         lands neither on the edge of a copper landing nor anywhere an end face can reach (README, XY)
CLEARANCE = 0.15        # mm copper to copper — the rule of hw33; the DRC rule of every board here, the demo's too (the
#                         patterns leave 0.53 mm between neighbouring pads)
PRINT_INSET = 0.3       # mm, print stays this far in from the board's edge

# What lies under a standoff's end face and under the socket's holes on the back of the upper deck: (copper, mask opened).
# Mask on bare laminate — what a board gets where nothing is drawn — is a fourth state nobody named; it is not offered.
# «copper_mask», and copper under the holes, are no written deck's: they are the parameter's third state, which the task
# names; a deck that uses one is one more name in VARIANTS.
SURFACES = {"bare": (False, True), "copper": (True, True), "copper_mask": (True, False)}
STATE = {"b": "bare", "c": "copper", "m": "copper_mask"}
# The upper decks written. A name IS its content — letter 1 under the end faces, letter 2 under the holes — so no table
# can say one thing and the board another. «bb» is what the founder was told for the holes (no copper, no mask; 00_07
# HW.9, the leg of the routing rule) and the same under the faces; «cb» differs in ONE thing, copper under the faces.
# They are the two the canon carries example thresholds for (CANON_EXAMPLE), one on each side of the 0.039 the ruling of
# 2026-11-12 was made on. Which becomes the routing rule is the founder's.
VARIANTS = ("bb", "cb")

# The threshold the bench measures against, on these surfaces: 02_01 §3.1, pos. 12, last ⊕ — a machine derivation of
# 2026-11-15, not the ruling. Δ* = (SWITCH − c + e + s₃)/2: c — how much the layer under an end face is thicker than the
# layer under the socket's holes; e — how much the socket's copper pads are thicker than the layer under an end face;
# s₃ — the seam of solder under the socket. The canon's example takes copper 0.035 and s₃ = 0; 0.035 is also KiCad's
# default stack-up here — the order's to set, not ours (README).
SWITCH = 0.078          # mm, ibid.
COPPER = 0.035          # mm, ibid. «при міді 0.035 мм і s₃ = 0»
CANON_EXAMPLE = {"bb": 0.057, "cb": 0.022}   # mm, ibid., «≈» — test_decks.py reads them out of the canon


def variant(name: str) -> tuple:
    """(under the end faces, under the holes) — the states a deck's name spells."""
    return STATE[name[0]], STATE[name[1]]


def threshold(face: tuple, holes: tuple, copper: float = COPPER, seam: float = 0.0, mask: float | None = None) -> float:
    """Δ* in mm for the surfaces (copper, mask opened) under the end faces and under the holes — the canon's form above.
    The mask's thickness enters only a surface under mask, and it is the order's: no default."""
    def layer(surface: tuple) -> float:
        cu, opened = surface
        if not opened and mask is None:
            raise ValueError(f"a surface under mask {surface}: the mask's thickness is the order's — pass it")
        return copper * cu + (0.0 if opened else mask)

    return (SWITCH - (layer(face) - layer(holes)) + (copper - layer(face)) + seam) / 2


def outline() -> list:
    """The contour of BOTH decks, [(x, y), …] in mm, closed by its first point: the smallest rectangle round every
    courtyard of either deck plus EDGE_FIELD, with one corner cut — the key against mating the pair turned round."""
    fw, clp = courtyard("FW"), courtyard("CLP")
    hx, hy = max(fw[0], clp[0]), max(fw[1], clp[1])
    r = max(STANDOFF["pad_d"] / 2 + COURTYARD_MARGIN, LANDING_D / 2)
    x1 = max(SPAN / 2 + r, hx) + EDGE_FIELD
    y0, y1 = min(-r, PAIR_OFFSET - hy) - EDGE_FIELD, max(r, PAIR_OFFSET + hy) + EDGE_FIELD
    return [(-x1 + KEY, y0), (x1, y0), (x1, y1), (-x1, y1), (-x1, y0 + KEY)]


KEEP_R = max(STANDOFF["pad_d"] / 2 + COURTYARD_MARGIN, LANDING_D / 2 + MASK_RELIEF)   # print stays outside this round a standoff


def clear_of_supports(x0: float, y0: float, x1: float, y1: float) -> bool:
    """Whether a box of print (mm) stays on the board PRINT_INSET in from its edge and off every surface the bench
    probes on a working face (deck_stack_gap_bench_sheet.md §9 p. 3): the pair's courtyard — its pads, the strip under
    the holes — and KEEP_R round a standoff — its pad and ring, the disc and its mask relief."""
    xs, ys = [x for x, _ in outline()], [y for _, y in outline()]
    (fw_x, fw_y), (clp_x, clp_y) = courtyard("FW"), courtyard("CLP")
    hx, hy = max(fw_x, clp_x), max(fw_y, clp_y)
    return (min(xs) + PRINT_INSET < x0 and x1 < max(xs) - PRINT_INSET and min(ys) + PRINT_INSET < y0 and y1 < max(ys) - PRINT_INSET
            and (x1 < PAIR[0] - hx or x0 > PAIR[0] + hx or y1 < PAIR[1] - hy or y0 > PAIR[1] + hy)
            and all(math.hypot(max(x0 - sx, 0, sx - x1), max(y0 - sy, 0, sy - y1)) > KEEP_R for sx, sy in STANDOFFS))


def print_spots() -> dict:
    """Where print stands, (x, y) in mm — on each deck's WORKING face only, the lower deck's top and the upper deck's back
    (the bench sheet, §9 pp. 1, 3: the base faces — the lower deck's bottom, the upper deck's top — carry mask and nothing
    else): «H1», «H2» just past each standoff's keep-out, on the pair's side; the kit number's write-in field one line
    under «H2» — by the standoff's pad on the lower deck, by its disc on the upper (§9 p. 3); the upper deck's name in
    the free corner beside the pair by H1. Ours, all of it; the build holds every box to clear_of_supports()."""
    x0, y1 = min(x for x, _ in outline()), max(y for _, y in outline())
    line = 1.6                                                 # mm, a line of 0.8 mm text and the gap under it
    return {"H1": (STANDOFFS[0][0], KEEP_R + 0.8), "H2": (STANDOFFS[1][0], KEEP_R + 0.8),
            "kit": (STANDOFFS[1][0], KEEP_R + 0.8 + line),
            "name": ((x0 - max(courtyard("FW")[0], courtyard("CLP")[0])) / 2, (KEEP_R + y1) / 2)}


# The ring an end face is probed on: the middle of the shoulder's ring, Ø2.8…Ø4.35 (W1) — ours; the end face spans it too,
# its bore (M2) and the chamfer at its mouth being undimensioned and well inside
RING_R = (STANDOFF["spigot_d"] + STANDOFF["body_d"]) / 4
FACES = {"lower": "top (working)", "upper": "back (working)", "stack": "top of the upper deck (base)"}


def points(node: dict) -> list:
    """The bench sheet's points (deck_stack_gap_bench_sheet.md §2.1, §4), [(name, deck, face, x, y)] in mm, in the frame
    above. P_H1 sits on H1's ring on the side away from G (§2.1), and so do the first of H1's three ring points and the
    point on its disc, which the sheet compares with it (§4.2, §4.3); H2 takes the mirror of H1's side. P_1, P_2 over the
    end columns of posts, on the pair's centreline; P_A, P_B across the standoffs' line, at the socket's courtyard on
    either side; the header's and the socket's points near either end, midway between the two outer columns of posts
    (cavities), on the pair's centreline — for the header the centre of four posts — so that each stands inside the
    nominal support of the part lying unsoldered on its leads (§2.2: a point past the outer leads tips the part under the
    probe); the sheet carries the header's seam wedge from them out to P_1, P_2 (§5); index 1 is the end of pad 1. Where
    the sheet does not fix a point, the choice is ours — README."""
    (h1x, h1y), (h2x, h2y) = STANDOFFS
    gx, gy = node["G"]
    d = math.hypot(h1x - gx, h1y - gy)
    side = {"H1": ((h1x - gx) / d, (h1y - gy) / d), "H2": ((gx - h1x) / d, (h1y - gy) / d)}
    at = {"H1": (h1x, h1y), "H2": (h2x, h2y)}

    def on(h: str, r: float, turn: float = 0.0) -> tuple:
        (ux, uy), c, s = side[h], math.cos(turn), math.sin(turn)
        return at[h][0] + r * (ux * c - uy * s), at[h][1] + r * (ux * s + uy * c)

    fw1, clp1, clp2 = pads("FW")[0], pads("CLP")[0], pads("CLP")[1]
    column = abs(fw1[1])                                       # the outer column of posts
    ends = {part: abs(pads(part)[0][1]) - PARTS[part]["pitch"] * INCH / 2   # each part's own two outer columns, midway
            for part in ("FW", "CLP")}
    pad_r = (STANDOFF["hole_d"] + STANDOFF["pad_d"]) / 4
    out = [(f"Z_pad{h}", "lower", *on(h, pad_r)) for h in at]
    out += [("Z_padF", "lower", PAIR[0] + fw1[1], PAIR[1] + fw1[2])]
    out += [(f"Z_{h}.{k + 1}", "lower", *on(h, RING_R, k * 2 * math.pi / 3)) for h in at for k in range(3)]
    out += [(f"Z_A{i + 1}", "lower", PAIR[0] + s * ends["FW"], PAIR[1]) for i, s in enumerate((-1, 1))]
    out += [(f"Z_disc.{h}", "upper", *on(h, RING_R)) for h in at]
    out += [("Z_strip", "upper", *PAIR)]
    out += [(f"Z_pad.{n}", "upper", PAIR[0] - x, PAIR[1] + y) for n, x, y, _w, _h in (clp1, clp2)]   # mirrored: on the back
    out += [(f"Z_E{i + 1}", "upper", PAIR[0] + s * ends["CLP"], PAIR[1]) for i, s in enumerate((-1, 1))]
    out += [(f"P_{h}", "stack", *on(h, RING_R)) for h in at]
    out += [(f"P_{i + 1}", "stack", PAIR[0] + s * column, PAIR[1]) for i, s in enumerate((-1, 1))]
    out += [(f"P_{ab}", "stack", PAIR[0], PAIR[1] + s * courtyard("CLP")[1]) for ab, s in (("A", -1), ("B", 1))]
    out += [("G", "stack", gx, gy)]
    return [(name, deck, FACES[deck], x, y) for name, deck, x, y in out]


def upper_surfaces(face: str, holes: str) -> list:
    """What build_decks.py draws on the back of the upper deck besides the socket: [(layer, kind, numbers)] in mm, layer
    «Cu» or «Mask» (a shape on the mask layer is an OPENING), kind «circle» (x, y, r) or «rect» (x0, y0, x1, y1).
    Under each end face — copper as a disc LANDING_D, the mask's opening MASK_RELIEF wider. Under the holes — the strip
    between the inner edges of the socket's two rows of pads, as long as its body: the mask opens right up to the pads;
    copper there is an island held CLEARANCE off them, so it reaches under the posts' axes but not under their outer
    faces (footprints.post_gap())."""
    out = []
    copper, opened = SURFACES[face]
    for x, y in STANDOFFS:
        out += [(layer, "circle", (x, y, r)) for layer, on, r in (("Cu", copper, LANDING_D / 2),
                                                                  ("Mask", opened, LANDING_D / 2 + MASK_RELIEF)) if on]
    copper, opened = SURFACES[holes]
    hx, hy = body("CLP")[0] / 2, post_gap()[0]
    for layer, on, half in (("Cu", copper, hy - CLEARANCE), ("Mask", opened, hy)):
        if on:
            out.append((layer, "rect", (-hx, PAIR_OFFSET - half, hx, PAIR_OFFSET + half)))
    return out


# The layout standoff_layout_fit.rb finds on the root package's target with conditions (1)–(2): its definitions are
# loaded up to its own top-level run, and the searcher is asked for its coordinates and for the constants it lays out.
PROBE = """
path = ARGV.shift
src = File.read(path)
eval(src[0...src.index(/^mirrors!$/)], TOPLEVEL_BINDING, path)
mirrors!
_, _, _, x = search(package_target(rigid_flex: false, through: false).first, false, :conditions)
ro = x[11].clamp(*R_O)
po = [ ro * Math.cos(x[10]), ro * Math.sin(x[10]) ]
puts JSON.generate(a: x[0, 2], b: x[2, 2], socket: x[7, 2], beta: x[9], g: G, p: F_SPLIT.map { |f| [ f * po[0], f * po[1] ] },
                   header: [ HDR_W, HDR_H ], socket_courtyard: [ SOCK_W, SOCK_H ], pad_courtyard_d: 2 * PAD_R,
                   face_d: 2 * SO_FACE_R)
"""


@functools.cache
def node_layout() -> dict:
    """The searcher's layout in the decks' frame (Ruby, ≈ 6 s). The standoffs' line is x; the searcher's A and B go to
    H1 and H2 or, if that would put the pair on −y, the frame is turned half round so it lands on +y — turned, never
    mirrored (the searcher's plan read as seen from above). The decks are symmetric about x = 0 but for the key and the
    label, so a node read mirrored would only swap which standoff the points stand by.
      G — the resultant of the pocket gasket's bead, pressing the upper deck from above (02_01 §3.1, pos. 25 ⊕, (1));
      P — the resultant of the two pogo pins under the lower deck, at either extreme split of their force ((2))."""
    out = subprocess.run(["ruby", "-e", PROBE, str(ROOT / "tools/firmware/standoff_layout_fit.rb")], cwd=ROOT,
                         check=True, capture_output=True, text=True).stdout
    n = json.loads(out)
    a, b = n["a"], n["b"]
    mid, span = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), math.dist(a, b)
    u = ((b[0] - a[0]) / span, (b[1] - a[1]) / span)

    def frame(q: list, k: int) -> tuple:
        d = (q[0] - mid[0], q[1] - mid[1])
        return k * (d[0] * u[0] + d[1] * u[1]), k * (d[0] * u[1] - d[1] * u[0])

    k = 1 if frame(n["socket"], 1)[1] > 0 else -1
    angle = math.degrees(n["beta"] - math.atan2(u[1], u[0])) % 180
    return {"span": span, "pair": frame(n["socket"], k), "angle": min(angle, 180 - angle), "G": frame(n["g"], k),
            "P": tuple(frame(p, k) for p in n["p"]), "B": "H2" if k == 1 else "H1",
            "header": tuple(n["header"]), "socket": tuple(n["socket_courtyard"]),
            "pad_courtyard_d": n["pad_courtyard_d"], "face_d": n["face_d"]}
