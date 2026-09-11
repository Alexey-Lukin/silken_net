# SilkenNet CAD Gallery — presentation visuals

Published snapshots from the `tools/cad` Code-as-CAD generators (PicoGK / CEM-native). **NOT SSOT** —
the source of truth is `tools/cad/cem/*.json` + the `.cs` generators; these are regenerable visuals for
fundraising / README / presentations. Rebuild with **`tools/cad/scripts/render_gallery.sh`**.

🔴 **«NOT SSOT» means «do not EDIT here», not «free to lag».** These files are committed and open straight
from GitHub, so they are the drawings an outsider actually reads — and nothing re-runs the script for you.
Measured 2026-09-09: the flange drawing here sat on its pre-2026-08-28 output for weeks, publishing the
invented alloy default and the dropped note lines that the fix had already removed from the generator.
**Change `Drawing.cs` or a CEM ⇒ re-run the script and commit the results in the SAME commit.**
Every `*.drawing.svg` here has a pin behind it (the `DrawingTests.Published_Gallery_…` family — content
+ frame-fit only, never byte-currency); ⛔ **the PNG renders have none** — they need a display, so a stale
render here is invisible to every gate we own. 🔑 Membership is stated as a RULE rather than a tally on
purpose: this line read «the two `*.drawing.svg` files» while four of them sat in the directory, and a
count beside a growing folder is right the day it is written and quietly narrower every day after.
**Publishing a new sheet means adding its gallery pin in the same commit** — that is what keeps the rule true.

| Visual | What | Generator command |
|---|---|---|
| [`ti_coin.drawing.svg`](ti_coin.drawing.svg) | Stage-2 coupon engineering drawing (Ø16 disc + eyelet + A≈2 cm², `01_01 §6.1`) | `draw cem/ti_coin.json` |
| `ti_coin.png` | Ti-coin 3D render (disc + potentiostat eyelet) | `render cem/ti_coin.json` |
| [`cathode_flange.drawing.svg`](cathode_flange.drawing.svg) | Деталь 3 cathode flange drawing (Ø25 + GND pad + PEEK iso-ring + 3× bayonet, `02_02 §1.2`) | `draw cem/cathode_flange.json` |
| `cathode_flange.png` | Cathode flange 3D render | `render cem/cathode_flange.json` |
| [`mechanical_lock_zone1.drawing.svg`](mechanical_lock_zone1.drawing.svg) | §4.3 ratchet shank, Zone-1 anchor end — barb envelope + DIN-471 groove (`01_01 §4.3`, HW.26) | `draw cem/mechanical_lock.zone1.json` |
| [`mechanical_lock_zone3.drawing.svg`](mechanical_lock_zone3.drawing.svg) | §4.3 ratchet shank, Zone-3 flange end — same generator, opposite ratchet lean | `draw cem/mechanical_lock.zone3.json` |
| [`anchor_zone1_pine.drawing.svg`](anchor_zone1_pine.drawing.svg) | Zone-1 anode **envelope card** — the carrier of the `01_02 §3.6` coating zone-map, with the zone boundary refused out loud (`00_07` HW.1) | `draw cem/anchor_zone1.pine.json` |
| [`zone2_sleeve.drawing.svg`](zone2_sleeve.drawing.svg) | Деталь 2 PEEK thermal-break sleeve — bore Ø11 / OD Ø15 (the WOUND in the tree) / 50 mm, press-fit PMI (`01_01 §1`/`§4.2`) | `draw cem/zone2_sleeve.json` |
| `anchor_zone1_pine.png` | Zone-1 gyroid anode — the ажурна Ti TPMS structure (pine SKU, `01_01 §5`) | `render cem/anchor_zone1.pine.json` |
| `anchor_zone1_pine_section.png` | Longitudinal **cutaway** (anode close-up): the **monolithic bus rod** (gold core) down the centre of the gyroid annulus (`01_01 §1.4`, HW.34) | `section cem/anchor_zone1.pine.json` |
| `anchor_axial_stack_section.png` | **Full bus PATH cutaway**: the rod (gold) runs from the anode, up the PEEK gap, through the cathode channel, to the flange-top pogo pad → the capsule (`01_01 §1.4`) | `section cem/anchor_axial_stack.json` |
| `anchor_assembly.png` | Capsule-end assembly (cathode flange ↔ PEEK radome, `02_02 §4.4`) | `render cem/anchor_assembly.json` |

- **Drawings** = SVG (vector — GitHub renders inline; the factory DXF is produced alongside by `draw`, but
  stays in `out/` regenerate-able). CEM-native: views + dimensions + GD&T computed from the CEM numbers.
- **Renders** = PicoGK native voxel screenshot (Ti-metallic material), TGA → PNG (presentation-sized 1600 px).
- STL is gitignored (too big — pine ≈ 189 MB); rebuild with `dotnet run -- build <cem>`.
- Render is viewer-window-gated (PicoGK opens a GL window + screenshots it): macOS desktop OK; a headless
  box needs a display (xvfb) or the f3d fallback on the STL.
