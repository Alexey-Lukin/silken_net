# HW.9 — test decks of the bench stack

The bench measures the one-sided shift of the gap beside the board-to-board pair on an assembled stack held by two standoffs without screws, and that shift picks the pair's code; the carrier of the stack is a pair of small boards, the test decks (⚖️ founder 2026-11-15; state and the legs: [`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) HW.9; the pair: [`02_01 §3.1`](../../../docs/02_01_Hardware_Architecture_and_BOM.md) pos. 12, the standoffs: pos. 25). This directory generates them by code:

- the **lower deck** — the Samtec FW-SM header and two Würth WA-SMSI standoffs on its front;
- the **upper deck** — the Samtec CLP-SM socket on its back and, there too, the surfaces the standoffs' end faces meet; one upper deck per variant of what lies under those faces and under the socket's holes, because that moves the very threshold the bench measures against (pos. 12, last ⊕).

Nothing else is on them: no nets, no parts beyond the pair and the standoffs. The ordering codes have one home — `02_01 §3.1`, pos. 12 and 25 — and are not repeated here. Buying the boards, the parts, a stencil and the reflow, the measurement protocol and the routing rule under the socket are not decided here: they are other legs of HW.9 and the founder's rulings.

## What is here

| File | Role |
|---|---|
| `footprints.py` | the land patterns (AGPL-3.0-or-later, like all tooling): one table of the vendors' numbers — each with its document, sheet, view and class, «read» ⊥ «derived» ⊥ «interpreted» — for the header, the socket and the standoff; pure geometry (`pads` · `body` · `courtyard` · `standoff_paste` · `post_gap` · `post_channel`, no KiCad) and the two drawers that put a pattern into a `pcbnew` board |
| `decks.py` | the decks' geometry, pure: the arrangement and `node_layout()`, which asks the node's searcher for its layout and its two resultants; the contour and its key; the parameter «what lies under the end faces and under the holes», the decks it names and the threshold those surfaces give (`threshold()`, the canon's form); where print may stand. Every number the canon does not give is marked as ours |
| `build_decks.py` | draws the three boards, runs every check on all of them, then writes `fab/` |
| `test_footprints.py` · `test_decks.py` | the patterns against the drawings; the standoff against the tree's earlier reading of its datasheet; the arrangement and the courtyards against the node (the searcher's tests need Ruby and are skipped where there is none); the threshold against the canon's form and example, read out of `02_01`; the surfaces against the parameter |
| `hw9_deck_lower` · `hw9_deck_upper_bb` · `hw9_deck_upper_cb` (`.kicad_pcb` · `.kicad_pro`) | the boards and their design rules (KiCad 10) — output of `build_decks.py` |
| `fab/<board>/gerbers/` · `<board>_cpl.csv` · `<board>_bom.csv` | text Gerbers and Excellon drill (KiCad's time stamps replaced by the title block's date), the placement file in the form `hw12_dmn2990ufa_breakout` writes, the parts with the home of their ordering codes — committed, as `hw12_dmn2990ufa_breakout` and `hw33_rf_axis3_boards` commit theirs |
| `build_demo.py` · `hw9_footprint_demo.kicad_pcb` · `.kicad_pro` | the first leg's proof of the pair's patterns: header and socket on one board, DRC, and a printout of the gap under the socket. Its flip check is now covered by the decks' stack check across two boards; it stays for the printout, and its project and DRC helpers serve `build_decks.py` |

The design outputs are hardware design and fall under **CERN-OHL-S-2.0** by the zone map in [`/NOTICE`](../../../NOTICE); KiCad's S-expressions have no comment syntax, so they carry no per-file tag.

## Sources

Fetched 2026-11-15; the PDFs are the vendors' and are not kept in the tree.

| | Document | Revision | URL |
|---|---|---|---|
| S1 | Samtec footprint and stencil «RECOMMENDED PCB LAYOUT FOR CLP-1XX-XX-XXX-D-XX» | W (10/2/2023, ECN-467634) | `https://suddendocs.samtec.com/prints/clp-1xx-xx-xxx-d-xx-footprint.pdf` |
| S2 | Samtec print `CLP-1XX-XX-XXX-D-XX-XX-XX` | DH | `https://suddendocs.samtec.com/prints/clp-1xx-xx-xxx-d-xx-xx-xx-mkt.pdf` |
| S3 | Samtec footprint «RECOMMENDED PCB LAYOUT FOR DOUBLE ROW FW-XX-XX-XX-D-XX» (`FW-D-SM`) | D | `https://suddendocs.samtec.com/prints/fw-d-sm-1-footprint.pdf` |
| S4 | Samtec stencil, the double-row FW stencil sheet, drawn on the four-position part (`FW-D-SM2`) | D | `https://suddendocs.samtec.com/prints/fw-d-sm-2-footprint.pdf` |
| S5 | Samtec print `FW-XX-XX-XX-D-XXX-XXX-XX-X-XX` | DG | `https://suddendocs.samtec.com/prints/fw-xx-xx-xx-d-xxx-xxx-xx-x-xx-mkt.pdf` |
| W1 | Würth Elektronik datasheet WA-SMSI, pages 1/6 (dimensions, land pattern, stencil, properties) and 2/6 (packaging); sha256 `39e7a13e3ee285b6…` | 001.003 (2025-12-31) | `https://www.we-online.com/components/products/datasheet/9774080243R.pdf` |

## Run

```bash
python3 -m pytest tools/pcb/hw9_stack_test_decks          # the geometry — any Python ≥ 3.10 with pytest; Ruby for the searcher's tests

~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
    tools/pcb/hw9_stack_test_decks/build_decks.py          # the decks (KiCad 10 in ~/Applications/KiCad, Ruby on the PATH)
~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -B \
    tools/pcb/hw9_stack_test_decks/build_demo.py           # the demo board + DRC + the gap printout
```

⛔ Keep `-B`: without it the interpreter writes `__pycache__/*.pyc` inside `KiCad.app`, which breaks the bundle's code signature (`codesign --verify --deep --strict` then reports «a sealed resource is missing or invalid»).

Every check runs on all three boards before `fab/` is touched — the decks against the node's searcher, each upper deck over the lower one, KiCad's DRC of each, the placement file against KiCad's pads. The boards themselves are written first, because DRC and the placement export read them from disk; a board that failed stays in the tree as a diff against the committed one.

## The decks

- **The frame** is the stack seen from above — KiCad's canvas of both boards at once, since each deck faces up: x along the line through the standoffs H1 → H2, y down (towards the pair), the origin midway between them.
- **The arrangement is the node's, as far as the node has one.** The node has no layout yet; `tools/firmware/standoff_layout_fit.rb` searches one under conditions (1)–(2) of the inset of pos. 25 and prints margins, not coordinates. `decks.node_layout()` loads the searcher and asks it for the coordinates of the layout it finds on the root package's target («the segment on the top only»); `decks.SPAN` and `decks.PAIR` are that layout rounded, and both the tests and the build hold them to it. One layout of a heuristic search on today's `radome.json`, not a ruling: the decks are a proxy, and the root move will shift it. The searcher's plan is read as seen from above and turned, never mirrored, into this frame — its standoff B is H1 here; the decks are symmetric about x = 0 but for the key and the name, so a mirrored reading would only swap which standoff the points below stand by.
- **The node's two resultants — what the layout was searched for** (the build prints them; today, in this frame):
  - **G** — the pocket gasket's bead, pressing the RF Deck from above: (−6.50, −0.42), ≈ 0.6 mm from H1's axis, inside its end face. Not marked: print there would stand on the support itself.
  - **P** — the two pogo pins pushing the Power Deck from below, at either extreme split of their force: (−0.95, −1.53) … (−1.89, −1.21). Marked on the lower deck's back as two open crosses — four ticks round each point, no print on the point.
  - **The deck's own middle**, (0, +2.29), lies outside the strip of the end faces (|y| ≤ 2.175), on the pair's side: a force there tilts the upper deck onto the pair, and the pair becomes the third support. **Input of the protocol: the force at G, the support at P** — as in the node, not at the middle of the deck.
- **Lower deck:** the header on the front at the pair's centre; each standoff on the front — a non-plated hole with a ring pad round it and the four paste sectors of the datasheet's stencil (W1). KiCad ships a footprint of this standoff, but its paste ends at Ø5.12 instead of Ø5.2 — less paste under the one joint whose height the bench is after — so the pattern is drawn here. In print, only the marks of P on the back.
- **Upper deck:** the socket on the back, at the same x, y, mirrored; under each end face a disc of the standoff's pad diameter, its mask opening 0.5 mm wider all round; under the socket's holes the strip between the inner edges of its two rows of pads, as long as its body. The mask opens right up to the pads; copper in that strip would be an island held off the pads by the clearance, so it reaches under the posts' axes but not their outer faces.
- **The parameter** `decks.SURFACES` names three states of a surface — bare laminate (no copper, mask opened) ⊥ copper (mask opened) ⊥ copper under mask; mask on bare laminate, what a board gets where nothing is drawn, is a fourth state nobody named and is not offered. **A deck's name is its content** — letter 1 under the end faces, letter 2 under the holes, `b` bare · `c` copper · `m` copper under mask — so no table can say one thing and the board another:

  | Deck | Under the end faces | Under the holes |
  |---|---|---|
  | `hw9_deck_upper_bb` | bare | bare |
  | `hw9_deck_upper_cb` | copper | bare |

  `bb` is what the founder was told for the holes (no copper and no mask), the same under the faces; `cb` differs in one thing. They are the two the canon carries an example threshold for, one on each side of the threshold the ruling of 2026-11-12 was made on (the form and the numbers: `02_01 §3.1`, pos. 12, last ⊕ — a machine derivation, not the ruling). The build reads the surfaces back off each board, puts them through that form at the example's copper and seam, and refuses a deck whose threshold is not the canon's example for its name. Copper under mask, and copper under the holes, are no written deck's — they are the parameter's third state, which the task names; a deck that uses one is one more name, and its threshold then needs the mask's thickness, which is the order's.
- **The key** against mating the pair turned half round (without –A the pair is symmetric under a half-turn): one corner of the contour cut, the same corner of both decks in the frame above. Turned round about the pair, a reversed mate puts the cut corners diagonally apart — and the end faces off their surfaces, which is what would spoil the measurement. It costs no field (the cut stays further from the standoff than the straight sides) and touches no surface either deck rests on.
- **The placement file** (`<board>_cpl.csv`) is KiCad's own `export pos` in the columns `hw12_dmn2990ufa_breakout` gives a fab: Designator · Mid X · Mid Y · Layer · Rotation, **Y up**. The socket reads `Bottom`, 180: KiCad's flip of a part onto the back mirrors it top–bottom, and its half-turn on top of that is the left–right mirror the decks need, so «socket pad n over header pad n» holds. The build reads that very text back as a fab reads it — a Bottom part is the pattern flipped top–bottom, then turned by Rotation, counter-clockwise seen from above — and refuses it unless every pad of the pair and every standoff's hole lands where KiCad has it. Without –A and without a pin-1 mark the socket is symmetric under a half-turn, so on the board either way round is the same placement; the pad numbers are ours (see «Numbering» below).
- **The upper deck's name** («U-BB», «U-CB») is printed on its front — the top face of the stack, away from the paste side — in the free corner beside the pair, over neither the pair nor a standoff, because the surfaces the bench will probe are the protocol's to name. The build checks the text's box as KiCad draws it; the marks go through the same check.
- **XY.** An end face (Ø4.35) sits on its landing (Ø5.3) with 0.475 mm to spare all round, nominal. What moves it there: the spigot's play in its hole (Ø2.8 in Ø3.0, W1), the hole's registration to the copper and the copper's on each board (the fab's), where each half of the pair settles on its pads, and the pair's own play — the stack is registered through the pair; no document tolerances that chain end to end. The mask opening stands a further 0.5 mm out, so a shifted mask lands neither on a `cb` landing's edge nor anywhere an end face can reach; under the holes the mask webs between the socket's pads lie between the posts' columns, so a shifted mask stays off the posts' paths there too.
- **The contour** is the smallest rectangle round every courtyard of either deck plus the edge field, with the cut corner; the generator prints its size (21.66 × 12.37 mm today).

### What is ours — the canon gives none of these

The edge field 1.0 mm from the outermost courtyard · the key: which corner, 2.0 × 2.0 mm · the surface under an end face: the standoff's own pad diameter, 0.475 mm wider than the face all round · the mask's relief 0.5 mm past it · the region «under the holes» and the copper island's clearance · the clearance 0.15 mm (the rule of `hw33`) · the courtyard margin 0.25 mm (the habit of `hw12` / `hw33`) · rounding the searcher's layout: spacing and offset to 0.01 mm, the pair midway along the line (the searcher: 0.027 mm off) with its rows parallel to it (0.63° off) · reading the searcher's plan as seen from above · 2 layers, 1.6 mm · print: 0.3 mm in from the edge, the name's text, size and place, the marks' ticks (0.2–0.45 mm out, 0.15 wide).

## The patterns

- **Header FW** (S3): pads 0.74 × 2.79 mm on a 1.27 pitch, 6.86 over the outer edges of the two rows; the connector outline 6.35 × 3.43 is the zone the drawing tells other components to avoid — drawn on the Fab layer and enclosed by the courtyard.
- **Socket CLP** (S1): pads 0.74 × 1.47 on a 1.27 pitch, 4.70 over the outer edges; the body 6.78 × 3.05 (S2) on the Fab layer. The vendor draws no zone for it.
- **Standoff** (W1): the hole Ø3.0 non-plated, the ring pad to Ø5.3, the paste a ring Ø3.1 / Ø5.2 cut into four sectors by two bridges 0.6 wide (one dimensioned, the other drawn the same), the body Ø4.35 on the Fab layer, the courtyard Ø5.8. The end face that meets the upper deck is a ring — the thread runs right through — and L 8.0 ±0.1 is drawn from the shoulder to that face: the solder under the shoulder adds to it, and the datasheet gives that solder no height, only the paste (150 µm min. — a property of the stencil order, not of the board file).
- **⚠️ The standoff comes with a tape on the very face that meets the upper deck.** W1, page 1, General Information: «In Tape & Reel packaging a Polyimide Tape is fixed on the top of the spacer for automatic assembly»; the order code's suffix `R` is, by the packaging table on page 2, «Tape & Reel, Polyimide Tape with flap» (`RR` — a round tape, `RX` — without one; whether `RX` exists at this length is not checked). The datasheet gives the tape no thickness; a polyimide film with its adhesive is commonly tens of microns — the order of the threshold. On the bench: take the tape off after reflow, clean the face, and only then measure each standoff's L.
- **Without –A neither pair pattern has a hole.** For the header the option cannot even be ordered at a .205″ stacker (S5, note 8).
- **Paste is the vendors' stencil.** Samtec's stencil sheets (S1 sheet 4; S4) draw the pair's apertures «same as FIG 1» — the pad, 1 : 1 — and that is what KiCad's default paste on these pads is; the thickness they ask for, .006″ (0.15 mm), belongs to the stencil order.
- **Numbering: the header's is read, the socket's is chosen.** The header is numbered as S3 draws it: 01 and 02 at one end, odd numbers in one row. The socket's numbering is chosen as the mirror of that, so that with the socket on the **bottom** of the upper board — `connector_footprint(…, bottom=True)`, mirrored left–right — socket pad n lies over header pad n; «post n enters cavity n» is then true by construction, the cavity's number being ours. The vendor's own numbering of the socket is not settled by its drawings: the footprint (S1) numbers nothing, and the print (S2) puts «02» and «01» by the two rows past one end of the entry-face view, with no leader to a contact. If those labels mark the end, our numbering is Samtec's; if they only name the rows, the ends are swapped — our 1…10 are their 9, 10, 7, 8, 5, 6, 3, 4, 1, 2 — and the rows stay. It matters only where this footprint meets someone else's footprint or symbol of one of the halves.
- **The gap under the socket.** The inner edge of a CLP pad stands 0.8763 mm from the pair's centreline, the outer face of a post 0.8382 mm (rows .050″ apart, post .016″ square — both REF in S5): 0.0381 mm between them in plan, nominal. The strip between the inner faces of the two rows of posts is 0.8636 mm (.034″), from the same two numbers. What moves a post against a pad is, the sway apart, toleranced in none of these drawings: where the socket's body settles on its pads, the post's play in the cavity across the rows (S2 does not dimension the cavity), the post's own position, its lean (S5: «2° MAX SWAY (EITHER DIRECTION)», drawn along the row), etch and registration of the copper. The pad beside a post is the pad of the cavity that post enters — the same net, so a post against that copper is a question of stack height, not of a short. The demo prints all of this; it is an input of the leg «routing rule under the CLP socket».

## What is checked, and what is not

Checked:

- every pair constant against the bracketed millimetres of the same dimension in its drawing (a slip of transcription, not a misreading); every standoff constant against the tree's earlier, independent reading of the same datasheet (`docs/protocols/hardware/deck_standoff_shortlist.md`, 2026-10-05) and the paste against the stencil's own arithmetic;
- against the node's searcher, run by the tests and by the build: the arrangement, the pair's courtyards, the standoff's pad (as KiCad has it on the board) and face; against the canon, the margin it prints for the node; condition (1) — G inside the strip of the end faces;
- the contour: the edge field on every side, the key not falling onto itself under a half-turn about the pair or about the standoffs' middle; where print may stand;
- the surfaces: for every pair of states, copper and mask under the whole end face, in the mask's relief, under each post's axis, at each post's outer face and on the pads, and nothing at a sample point away from all of them; the threshold of each written deck against the canon's example, from the canon's own text;
- in the build, on what KiCad reports: each upper deck over the lower one, contour on contour — socket pad n over header pad n for all ten, one surface under every post's axis and one under both end faces, the one its name spells, and its threshold the canon's example; DRC of each board (0 violations, 0 unconnected); the placement file, read back as a fab reads it, against KiCad's pads; the name's box clear of the supports.

Each check was seen to fail on a mutation: a standoff's pad, length or paste bridge, the letters' meaning, the canon's examples swapped, a surface state, the mask strip, the mask's relief, the standoffs' spacing, the pair's offset, G — in the tests; the letters' meaning, mask on bare laminate, the standoff's pad, the spacing, the placement file's flip, Y and rotation, the flip direction, the back mask, the name over a standoff, a raised clearance — in the build.

Seen by hand, not checked by the build: two runs give the same hashes of every output.

Not checked — the ceiling of this leg:

- **Decks reflowed by hand do not measure the serial assembler's solder layer** — under the standoffs' shoulders and under the pair — and that layer is the main term of the shift that picks the code (the weakest link the founder was given, 2026-11-15). The protocol leg has to name it.
- **The measurement means something only on a flat finish.** HASL can leave tens of microns of uneven solder on exposed copper (no number for it in the tree) — on the `cb` landings, where it is c itself, and on the socket's pads in every deck, where it is e — the order of the threshold; ENIG is flat. The canon's row for the node's boards (pos. 8) says «HASL/ENIG». The finish is the procurement submission's, not this file's: the job file says `Finish: None` — KiCad's default, deliberately left — and its copper 0.035 and mask 0.01 are KiCad's defaults too (0.035 is also the copper of the canon's example the build checks against). Board thickness: 1.6 mm here also keeps the standoff's 1.4 mm spigot inside the lower deck, so the deck sits flat on whatever supports it.
- **Bow and twist of the decks.** The canon takes the decks flat and rigid; the upper deck carries copper on its back only, and neither the bow nor the twist of either deck is known — an input of the protocol (measure them, or support so they do not enter).
- **No surface for the measurement is marked.** Neither the bench leg nor the canon names between which surfaces to measure; reference marks come after the protocol does.
- **Inputs of the protocol, gathered:** the force at G and the support at P; the tape off and each standoff's L measured after; between which surfaces; bow and twist; hand reflow ≠ the serial solder layer; which threshold holds for the finish ordered.
- **The socket's height base** — the print measures it from the bottom of the leads at the bend, while the inset of pos. 12 and the request sheet also say «above the board» — is the other half of the generator's leg and lives in the canon, not here.
- **The patterns have met no part.** DRC judges the copper against our rules, not against the connector or the standoff; the first real check is a part on a board. Where the leads end on the pads (the toe) is not computed — the lead spans are in S2 and S5.
- **S3 and S4 have no text layer** — their numbers were read off a raster by eye; S1, S2, S5 and W1 were read as text and on the raster.
- **Samtec's numbering of the socket** — see above; and no print shows a pin-1 mark on either body.
- **Five positions only**: the geometry takes any count, the drawers place the ten-pin pair.
- **CI** lints these files with `ruff`; neither the tests nor the generator run there.
