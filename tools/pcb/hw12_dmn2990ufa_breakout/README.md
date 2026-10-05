# HW.12 — DMN2990UFA breakout (X2-DFN0806-3 → 2.54 mm header)

The clamp key of candidate P1 (`DMN2990UFA`, ⚖️ topology — [`02_03 §4`](../../../docs/02_03_BQ25570_MPPT_Nano_Power.md) §Б) comes only in X2-DFN0806-3, 0.6 × 0.8 mm, which no breadboard and no hand adapter takes. This board lets the breadboard measure the IDSS of **that** key — the fourth measurement of the money fork ARCH.8 — instead of waiting for the first PCBA. Why not an adapter: [`02_04 §4.1`](../../../docs/02_04_Bench_Build_Guide.md), row HW.12. State and the order leg: [`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) HW.12.

## What is here

| File | Role |
|---|---|
| `build_board.py` | the source — generates everything below (AGPL-3.0-or-later, like all tooling) |
| `hw12_dmn2990ufa_breakout.kicad_pcb` · `.kicad_pro` | the board and its design rules (KiCad 10) |
| `fab/gerbers/` | Gerber layers + Excellon drill, as text |
| `fab/hw12_dmn2990ufa_breakout_bom.csv` · `_cpl.csv` | JLCPCB PCBA: BOM (Q1 = `DMN2990UFA-7B`, LCSC `C151598`) and placement |

The design outputs are hardware design and fall under **CERN-OHL-S-2.0** by the zone map in [`/NOTICE`](../../../NOTICE); KiCad's S-expressions have no comment syntax, so they carry no per-file tag.

Rebuild (KiCad 10 installed in `~/Applications/KiCad`):

```bash
~/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 \
    tools/pcb/hw12_dmn2990ufa_breakout/build_board.py
```

The run fails on any DRC violation or unconnected item before it writes fabrication files, and it also writes `fab/hw12_dmn2990ufa_breakout_gerbers.zip` for the upload (ignored by git — it is rebuilt from the text gerbers).

## The board

- **12.70 × 11.43 mm, 2 layers, all copper on top, no pour.** Header order **G · S · D** (pin 1 = G) — the order that routes every net on one layer without a via.
- **Land pattern from the datasheet, not from a library** (KiCad ships none): Diodes DS35765 Rev. 3-2, p. 5 «Suggested Pad Layout» — drain pad 0.450 × 0.475 on top, two pads 0.200 × 0.375 below at a 0.350 pitch, 1.000 overall. Pin assignment from p. 1 «Top View» (D left, S top right, G bottom right), cross-checked against the p. 5 package outline (a bottom view, mirrored): with the drain pad on top, G sits bottom-left and S bottom-right.
- **Clearance 0.127 mm (5 mil)** in the project rules — the datasheet pattern leaves 0.150 mm between pads.

## Ordering notes (👤)

1. **Check the rotation of Q1 in JLCPCB's placement preview.** The CPL says 0° with the drain pad pointing up the board; JLCPCB's own library orientation for `C151598` is theirs, and a wrong angle swaps G and S on a part this small.
2. **Order some boards bare.** The measurement is nanoamperes, and leakage across the board surface between the D and S tracks belongs to it. A bare board measured with the same instrument at the same voltage is the control: what it shows is not the key's IDSS. The D track is kept away from S everywhere but at the package itself; there is no copper pour for the same reason.
3. **Hand-solder the header** — it is not in the BOM (a three-pin THT part does not justify THT assembly).
