# HW.9 — test decks of the bench stack: land patterns of the board-to-board pair

The bench stack is measured on a pair of small boards — a lower deck with the header and two standoffs, an upper deck with the socket (⚖️ founder 2026-11-15; state and the legs: [`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) HW.9; the pair itself: [`02_01 §3.1`](../../../docs/02_01_Hardware_Architecture_and_BOM.md) pos. 12). KiCad ships no footprint for either half, so the first leg — and this directory so far — is the two land patterns drawn by code from the vendor's drawings: the Samtec FW-SM header and the Samtec CLP-SM socket, five positions by two rows, both without the –A option (the ordering codes have one home — `02_01 §3.1`, pos. 12 — and are not repeated here). The decks themselves are the next leg.

## What is here

| File | Role |
|---|---|
| `footprints.py` | the source of the patterns (AGPL-3.0-or-later, like all tooling): one table of the drawings' numbers — each with its drawing, sheet, view and its class, «read» ⊥ «derived» ⊥ «interpreted» — a pure geometry (`pads` · `body` · `post_gap` · `post_channel`, no KiCad) and `connector_footprint()`, which draws a pattern into a `pcbnew` board, on the front or mirrored onto the back |
| `test_footprints.py` | the geometry against the drawings, and the socket's numbering against the header's |
| `build_demo.py` | generates the demo board below, checks the mate on what KiCad reports after its flip, runs DRC, prints the gap between the socket's pad and the path of the post |
| `hw9_footprint_demo.kicad_pcb` · `.kicad_pro` | the demo board and its design rules (KiCad 10) — output of `build_demo.py`: the header on the front, the socket on the back at the same place. A proof of the patterns, not a deck: nothing here is ordered, so there is no `fab/` |

The design outputs are hardware design and fall under **CERN-OHL-S-2.0** by the zone map in [`/NOTICE`](../../../NOTICE); KiCad's S-expressions have no comment syntax, so they carry no per-file tag.

## Sources

Samtec, fetched 2026-11-15; the PDFs are the vendor's and are not kept in the tree. Only S1 carries a revision date in its stamp.

| | Document | Revision | URL |
|---|---|---|---|
| S1 | footprint and stencil «RECOMMENDED PCB LAYOUT FOR CLP-1XX-XX-XXX-D-XX» | W (10/2/2023, ECN-467634) | `https://suddendocs.samtec.com/prints/clp-1xx-xx-xxx-d-xx-footprint.pdf` |
| S2 | print `CLP-1XX-XX-XXX-D-XX-XX-XX` | DH | `https://suddendocs.samtec.com/prints/clp-1xx-xx-xxx-d-xx-xx-xx-mkt.pdf` |
| S3 | footprint «RECOMMENDED PCB LAYOUT FOR DOUBLE ROW FW-XX-XX-XX-D-XX» (`FW-D-SM`) | D | `https://suddendocs.samtec.com/prints/fw-d-sm-1-footprint.pdf` |
| S4 | stencil the double-row FW stencil sheet, drawn on the four-position part (`FW-D-SM2`) | D | `https://suddendocs.samtec.com/prints/fw-d-sm-2-footprint.pdf` |
| S5 | print `FW-XX-XX-XX-D-XXX-XXX-XX-X-XX` | DG | `https://suddendocs.samtec.com/prints/fw-xx-xx-xx-d-xxx-xxx-xx-x-xx-mkt.pdf` |

## Run

```bash
python3 -m pytest tools/pcb/hw9_stack_test_decks          # the geometry — any Python ≥ 3.10 with pytest, no KiCad

~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
    tools/pcb/hw9_stack_test_decks/build_demo.py           # the demo board + DRC (KiCad 10 in ~/Applications/KiCad)
```

⛔ Keep `-B`: without it the interpreter writes `__pycache__/*.pyc` inside `KiCad.app`, which breaks the bundle's code signature (`codesign --verify --deep --strict` then reports «a sealed resource is missing or invalid»).

The demo run refuses a socket pad that KiCad's flip did not put over the header pad of the same number, and fails on any DRC violation or unconnected item; a board that failed stays in the tree as a diff against the committed one.

## The patterns

- **Header FW** (S3): pads 0.74 × 2.79 mm on a 1.27 pitch, 6.86 over the outer edges of the two rows; the connector outline 6.35 × 3.43 is the zone the drawing tells other components to avoid — drawn on the Fab layer and enclosed by the courtyard.
- **Socket CLP** (S1): pads 0.74 × 1.47 on a 1.27 pitch, 4.70 over the outer edges; the body 6.78 × 3.05 (S2) on the Fab layer. The vendor draws no zone for it.
- **Without –A neither pattern has a hole.** For the header the option cannot even be ordered at a .205″ stacker (S5, note 8).
- **Paste is the vendor's stencil.** Both stencil sheets (S1 sheet 4; S4) draw the apertures «same as FIG 1» — the pad, 1 : 1 — and that is what KiCad's default paste on these pads is. The thickness they ask for, .006″ (0.15 mm), is a property of the stencil order, not of the board file.
- **Numbering: the header's is read, the socket's is chosen.** The header is numbered as S3 draws it: 01 and 02 at one end, odd numbers in one row. The socket's numbering is chosen as the mirror of that, so that with the socket on the **bottom** of the upper board — `connector_footprint(…, bottom=True)`, mirrored left–right — socket pad n lies over header pad n; «post n enters cavity n» is then true by construction, the cavity's number being ours. The vendor's own numbering of the socket is not settled by its drawings: the footprint (S1) numbers nothing, and the print (S2) puts «02» and «01» by the two rows past one end of the entry-face view, with no leader to a contact. If those labels mark the end, our numbering is Samtec's; if they only name the rows, the ends are swapped — our 1…10 are their 9, 10, 7, 8, 5, 6, 3, 4, 1, 2 — and the rows stay. It matters only where this footprint meets someone else's footprint or symbol of one of the halves.
- **KiCad records the mirror as a flip plus a half-turn**: the socket's footprint reads 180°, which a placement file of the decks will have to respect.
- **The gap under the socket.** The inner edge of a CLP pad stands 0.8763 mm from the pair's centreline, the outer face of a post 0.8382 mm (rows .050″ apart, post .016″ square — both REF in S5): 0.0381 mm between them in plan, nominal. The strip between the inner faces of the two rows of posts is 0.8636 mm (.034″), from the same two numbers. What moves a post against a pad is, the sway apart, toleranced in none of these drawings: where the socket's body settles on its pads, the post's play in the cavity across the rows (S2 does not dimension the cavity), the post's own position, its lean (S5: «2° MAX SWAY (EITHER DIRECTION)», drawn along the row), etch and registration of the copper. The pad beside a post is the pad of the cavity that post enters — the same net, so a post against that copper is a question of stack height, not of a short. The demo prints all of this; it is an input of the leg «routing rule under the CLP socket», and the rule is the founder's to rule.

## What is checked, and what is not

Checked:

- every constant against the bracketed millimetres of the same dimension in its drawing — the bracket is the vendor's conversion of that same number, so this catches a slip of transcription, not a misreading of the drawing;
- count, pitch and symmetry of both patterns, the header's numbering against S3, the socket's numbering against the header's (code against code — the mirror is written by the test);
- KiCad's flip itself, in the demo: socket pad n on the back, in the column and on the side of header pad n, for all ten;
- DRC of the demo board against a 0.15 mm clearance.

Each was seen to fail: the tests on a changed pitch and on a turned socket numbering, the demo on a wrong flip direction and on a raised clearance rule.

Not checked — the ceiling of this leg:

- **The patterns have met no part.** DRC judges the copper against our rules, not against the connector; the first real check is a part on a board. Where the leads end on the pads (the toe) is not computed here — the lead spans are in S2 and S5.
- **S3 and S4 have no text layer** — their numbers were read off a raster by eye; the other three were read as text and on the raster.
- **Samtec's numbering of the socket** — see above; and no print shows a pin-1 mark on either body. Without –A both halves are symmetric under a half-turn: the pair can be mated turned round, and nothing in the patterns prevents it. The demo and the decks carry no nets; a board that does will need a key (the standoffs or the silkscreen).
- **Mask and copper under the socket.** No drawing gives a mask rule, a keep-out or a tolerance for either footprint; pads take the board's default mask.
- **The standoff footprint, the deck generator and the measurement protocol** — the next legs of HW.9.
- **Five positions only**: the geometry takes any count, `connector_footprint()` places the ten-pin pair.
- **CI** lints these files with `ruff`; neither the test nor the generator runs there.
