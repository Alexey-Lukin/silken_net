# HW.33 — test boards of the RF mock-up, axis 3 (an antenna booster on a ground of our contour)

Axis 3 measures the efficiency of an antenna booster on a ground the size of the node's board — the number the ruling «for the small ground we pay in efficiency» stands on, and the one no evaluation board measures by construction ([`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md); procedure — [`rf_mockup_bench_sheet`](../../../docs/protocols/hardware/rf_mockup_bench_sheet.md) §5). The sheet asks for two diameters — the sentinel Ø20.37 and Ø19.37 — and for both boosters that fit the contour where possible, so there are four boards. State and the order leg: [`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) HW.33.

## What is here

| File | Role |
|---|---|
| `build_boards.py` | the source — generates everything below (AGPL-3.0-or-later, like all tooling); its header carries the vendor's footprint and evaluation-board numbers with the page each was read on, and every layout choice that is ours |
| `hw33_axis3_<booster>_d<Ø>.kicad_pcb` · `.kicad_pro` | the four boards and their design rules (KiCad 10) — `nn02224`/`nn02201` × `d20p37`/`d19p37` |
| `fab/<board>/gerbers/` | Gerber layers + Excellon drill, as text |
| `fab/<board>/<board>_bom.csv` | what goes on the board, for hand assembly |

The design outputs are hardware design and fall under **CERN-OHL-S-2.0** by the zone map in [`/NOTICE`](../../../NOTICE); KiCad's S-expressions have no comment syntax, so they carry no per-file tag.

Rebuild (KiCad 10 installed in `~/Applications/KiCad`):

```bash
~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 \
    tools/pcb/hw33_rf_axis3_boards/build_boards.py
```

The run refuses a placement whose pads or booster body leave the contour, or a part that reaches into the clearance area; a board that fails DRC (any violation or unconnected item) is deleted with its project before any fabrication file is written; it also writes `fab/<board>/<board>_gerbers.zip` for the upload (ignored by git — it is rebuilt from the text gerbers).

## The boards

- **A disc of the contour, 2 layers, FR4 1.6 mm, ground poured on both layers and stitched.** The disc is the radiator: a booster excites the ground it sits on.
- **The booster at the top edge, in a clearance segment only 1.0 mm deeper than its pads.** The vendor's evaluation boards give the booster an 11 mm strip; ours is the narrowest the footprint allows, on purpose — the node's board budget has no room for a wide one, so the board measures what the product can have, and the number comes out more pessimistic than a wide clearance would give. Narrowest is not small: the segment over the chord is ≈ 30–33 % of the disc for `NN02-224` and ≈ 18–20 % for `NN02-201` (Ø20.37 · Ø19.37) — every run prints it in mm². The width is ratified (founder, 2026-10-12): the narrowest — grounds, price and weakest link in the bench sheet §5. Changing the strip is one constant in the generator, not a new design.
- **The feed:** a grounded coplanar line ≈ 51 Ω, then four 0603 sites — A shunt · B series · C shunt · D series (D fitted with 0 Ω) — and a U.FL. The VNA starts from the values of the smallest published ground for `NN02-224`, 40 × 20 — 27 nH · 8.2 nH · 2.0 pF ([`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md)) — whose topology this pass did not see; the board takes a π (A B C) as well as a T (B C D). The vendor's ISM application note has six networks in our band, all read off their schematics: two L on 131 × 60 (863–870 MHz: 30 nH series + 20 nH shunt — B + C) and four T, among them the CR80 board's 863–870 MHz one (30 nH series · 13 nH shunt · 3 nH series — B · C · D) on a 75 × 54 ground, the smallest seen; not one is a π. The vendor's values are a starting point for the VNA, never ours.
- **Stitching:** a via 1.2 mm from each shunt's ground pad, one within 1.2–1.8 mm of a ground pad of the U.FL (its other ground pad, against the clearance or the edge, has its nearest via 3–4 mm away on three of the boards), a grid over the ground, and a fence along the line where the parts' pads leave room — at 868 MHz (λ_g ≈ 208 mm) every one of those spacings is far inside λ/20.
- **The mounting pad of the booster is left unconnected** — both manuals say it must not be grounded. The booster's body is placed as well as its pads: the `NN02-201` body (7.0 × 3.0) is wider than its pads, so it is the body that meets the contour.

## Ordering notes (👤)

1. **Order the boards bare** — nothing here needs a PCBA house: every matching part is chosen on the VNA, and the booster's two pads hand-solder.
2. **Parts:** the boosters `NN02-224` and `NN02-201` (from a distributor of Ignion), Hirose `U.FL-R-SMT-1`, a U.FL → SMA cable, and a tuning set around the vendor's values in the parts the vendor itself names — Murata LQW18AN (0603) inductors, LQW15AN (0402) for the smallest ones, GJM1555 (0402) capacitors; a 0402 part sits on the 0603 sites by hand.
3. **Clip ferrite chokes on the feeding cable** — on a ground of ≈ λ/17–18 (Ø20.37 · Ø19.37 against λ ≈ 345 mm at 868 MHz) the cable becomes part of the radiator, and without chokes the reading is optimistic (bench sheet §5).
4. The instruments of axis 3 — VNA, a Wheeler cap ≥ 55 mm, a step attenuator — are in the bench's instrument list; without them the boards wait.
