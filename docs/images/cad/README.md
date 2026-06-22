# SilkenNet CAD Gallery — presentation visuals

Published snapshots from the `tools/cad` Code-as-CAD generators (PicoGK / CEM-native). **NOT SSOT** —
the source of truth is `tools/cad/cem/*.json` + the `.cs` generators; these are regenerable visuals for
fundraising / README / wiki. Rebuild any time: **`tools/cad/scripts/render_gallery.sh`**.

| Visual | What | Generator command |
|---|---|---|
| [`ti_coin.drawing.svg`](ti_coin.drawing.svg) | Stage-2 coupon engineering drawing (Ø16 disc + eyelet + A≈2 cm², `01_01 §6.1`) | `draw cem/ti_coin.json` |
| `ti_coin.png` | Ti-coin 3D render (disc + potentiostat eyelet) | `render cem/ti_coin.json` |
| [`cathode_flange.drawing.svg`](cathode_flange.drawing.svg) | Деталь 3 cathode flange drawing (Ø25 + GND pad + PEEK iso-ring + 3× bayonet, `02_02 §1.2`) | `draw cem/cathode_flange.json` |
| `cathode_flange.png` | Cathode flange 3D render | `render cem/cathode_flange.json` |
| `anchor_zone1_pine.png` | Zone-1 gyroid anode — the ажурна Ti TPMS structure (pine SKU, `01_01 §5`) | `render cem/anchor_zone1.pine.json` |
| `anchor_zone1_pine_section.png` | Longitudinal **cutaway**: the **monolithic bus rod** (gold core) down the centre of the gyroid annulus (`01_01 §1.4`, HW.34) | `section cem/anchor_zone1.pine.json` |
| `anchor_assembly.png` | Capsule-end assembly (cathode flange ↔ PEEK radome, `02_02 §4.4`) | `render cem/anchor_assembly.json` |

- **Drawings** = SVG (vector — GitHub renders inline; the factory DXF is produced alongside by `draw`, but
  stays in `out/` regenerate-able). CEM-native: views + dimensions + GD&T computed from the CEM numbers.
- **Renders** = PicoGK native voxel screenshot (Ti-metallic material), TGA → PNG (presentation-sized 1600 px).
- STL is gitignored (too big — pine ≈ 189 MB); rebuild with `dotnet run -- build <cem>`.
- Render is viewer-window-gated (PicoGK opens a GL window + screenshots it): macOS desktop OK; a headless
  box needs a display (xvfb) or the f3d fallback on the STL.
