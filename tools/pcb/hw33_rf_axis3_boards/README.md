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

The run refuses a placement that leaves the contour or reaches into the clearance area, and fails on any DRC violation or unconnected item before it writes fabrication files; it also writes `fab/<board>/<board>_gerbers.zip` for the upload (ignored by git — it is rebuilt from the text gerbers).

## The boards

- **A disc of the contour, 2 layers, FR4 1.6 mm, ground poured on both layers and stitched.** The disc is the radiator: a booster excites the ground it sits on.
- **The booster at the top edge, in a clearance segment only 1.0 mm deeper than its pads.** The vendor's evaluation boards give the booster an 11 mm strip; ours is minimal on purpose — the node's board budget has no room for a wide one, so the board measures what the product can have, and the number comes out more pessimistic than a wide clearance would give. Changing that is one constant in the generator, not a new design.
- **The feed:** a grounded coplanar line ≈ 51 Ω, then four 0603 sites — A shunt · B series · C shunt · D series (D fitted with 0 Ω) — and a U.FL. The evaluation board's L network (30 nH in series from the booster, 20 nH shunt at the port) goes on B + C; a π uses A B C, a T uses B C D. The vendor's values are a starting point for the VNA, never ours.
- **The mounting pad of the booster is left unconnected** — the vendor's manual says it must not be grounded.

## Ordering notes (👤)

1. **Order the boards bare** — nothing here needs a PCBA house: every matching part is chosen on the VNA, and the booster's two pads hand-solder.
2. **Parts:** the boosters `NN02-224` and `NN02-201` (from a distributor of Ignion), Hirose `U.FL-R-SMT-1`, a U.FL → SMA cable, and a 0603 kit of high-Q inductors and capacitors in the vendor's family (Murata LQW18 · GJM) around the evaluation-board values.
3. **Clip ferrite chokes on the feeding cable** — on a ground of ≈ λ/22 the cable becomes part of the radiator, and without chokes the reading is optimistic (bench sheet §5).
4. The instruments of axis 3 — VNA, a Wheeler cap ≥ 55 mm, a step attenuator — are in the bench's instrument list; without them the boards wait.
