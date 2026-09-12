# `tools/cad/` — SilkenNet Code-as-CAD (PicoGK)

The "set up once" home for the project's geometry surface — the CAD peer to
`tools/ml/` (ML), `tools/in_silico/` (chemistry), `contracts/` (Solidity),
`firmware/` (edge), and Rails (backend). A small, deterministic **Computational
Engineering Model (CEM)**: geometry is *computed from intent* in code + `cem/*.json`,
in the spirit of LEAP 71 **Noyron** — an algorithm, not generative ML.

> **Canon SSOT:** [`01_02 §6`](../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (PicoGK
> stack + Noyron methodology) · [`01_01 §5`](../../docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md)
> (anchor geometry) · tracker [`00_07` HW.1 / HW.33](../../docs/00_07_Action_Plan_Tracker.md).
> The geometry numbers are owned there; the `.cs` generators + `cem/*.json` are the
> Git-SSOT, the STL is a derived artifact (gitignored).

## The core idea — CEM, not GUI, not generative-AI

```
   cem/*.json  (parameters, Git-SSOT)
        │  drives
   src/SilkenCad/*.cs  (deterministic generators)  ──►  PicoGK voxel / SDF
        │                                                      │
        ▼  build                                               ▼  verify
   out/<name>.stl  (artifact, gitignored)         out/<name>.metrics.json
                                                   (porosity, bbox, tris — golden-metrics)
```

An agent **writes the generator** (reviewable `.cs`); the generator **computes the
geometry** deterministically. Parity is on derived metrics, never the raw STL bytes.

## Layout

| Path | What |
|---|---|
| `cem/*.json` | CEM manifests (Git-SSOT inputs) — e.g. `ti_coin`, `anchor_zone1.pine` |
| `src/SilkenCad/Program.cs` | CLI: `smoke` / `build <cem>` / `verify <cem>` (headless `Library.Go`) · `scan <cem>` (wallParam window, pure) · `draw <cem>` (engineering drawing SVG+DXF, pure-managed) · `render` / `section <cem>` (PicoGK native-viewer screenshot / cutaway → `out/*.png`) |
| `src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw`): SVG (human) + DXF via netDxf (factory, opens in AutoCAD/Fusion). Pure-managed; consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text). ⚠️ The SVG has a `viewBox` and therefore CLIPS; the DXF has no viewport and clips nothing — so a layout defect here always reads «reviewer sees LESS than the factory». The three symptoms of that (silent 22-char title-block truncation · title block drawn past the canvas · unwrapped notes running off the frame) are FIXED: truncation is announced (`… → NOTES` / `… → FOOTER`), notes word-WRAP, and the canvas height is COMPUTED from content. The rule survives the fix — check any notes/title-block change in BOTH readers |
| `src/SilkenCad/TiCoin.cs` | Stage-2 in-vitro coupon — disc + eyelet (`01_01 §6.1`) |
| `src/SilkenCad/Zone1Anode.cs` | Zone-1 gyroid anode + the custom `CartesianGyroid` SDF |
| `src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity/bbox/tris) + LEAP `Measure.fGetSurfaceArea` |
| `src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + flood-fill (open/closed-pore, percolation, solid-island, specific-surface) |
| `src/SilkenCad/WallScan.cs` | wallParam critical-threshold scan → the CEM working window (printable + open-pore + percolating); pure-managed, no render |
| `src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` ratchet-barb + DIN-471 groove SDF on the shank (Zone-1 solid monolithic / Zone-3 channelled) + self-support metric |
| `src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs + radial bayonet lugs + bus channel + O-ring groove |
| `src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + bayonet socket + PCB cavity + O-ring groove |
| `src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, 02_02 §4.4): bayonet datum + Z/MATE-Ø/RF mismatch + skirt/inboard candidates |
| `src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK thermal-break sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (press-fit, smooth bore) |
| `src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, 02_02 §4.5): press-fit interference (Zone1↔2 line-to-line · Zone2↔3 = Ø9-in-Ø11 clearance F1) + insertion budget + span |
| `src/SilkenCad.Leap/` | vendored LEAP source compiled in (relaxed warnings — not ours) |
| `extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |
| `tests/SilkenCad.Tests/` | xUnit scaffold |
| `global.json` · `Directory.{Build,Packages}.props` · `.editorconfig` | pinned SDK + CPM + lint |

## Verify locally

```bash
export PATH="$HOME/.dotnet:$PATH"            # .NET 9 SDK (pinned in global.json)
cd tools/cad
dotnet build SilkenCad.sln                                                  # 0W/0E
dotnet run --project src/SilkenCad -- smoke                                 # foundation self-test
dotnet run --project src/SilkenCad -- build  cem/anchor_zone1.pine.json     # → out/*.stl
dotnet run --project src/SilkenCad -- verify cem/anchor_zone1.pine.json     # → out/*.metrics.json (exit 0/1)
dotnet run --project src/SilkenCad -- scan   cem/anchor_zone1.pine.json     # → out/*.wallscan.json (wallParam working window)
dotnet run --project src/SilkenCad -- draw   cem/ti_coin.json               # → out/*.svg + *.dxf (engineering drawing, pure-managed)
dotnet run --project src/SilkenCad -- render cem/anchor_zone1.pine.json     # → out/*.png (PicoGK viewer; needs a display — macOS desktop, not headless CI)
```

## Gotchas (hard-won — read before touching the generators)

- **Headless:** run inside `Library.Go(voxel, task, bEndAppWithTask:true)`. The v1.6
  `new Library()` headless pattern is stale in v2.2 (runtime aborts: "relies on
  Library::Go"). `bEndAppWithTask:true` exits with the task → no viewer block → CI-able.
- **Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`**, *not*
  `voxBounding.voxIntersectImplicit(...)`: the latter yields a malformed (background-0)
  OpenVDB level set at fine voxel on thin bored parts → an **uncatchable native abort**
  (`libc++abi … ValueError: expected grid A outside value > 0, got 0`).
- **A FILLED (solid) body must come from ShapeKernel `voxConstruct`, NOT the SDF ctor.**
  `new Voxels(IImplicit, BBox3)` builds a **narrow-band** field (voxels near the surface only),
  so a solid core falls outside the band and renders as a **hollow shell** (measured: a Ø11 shank
  read ~17 mm³ instead of ~1700). The gyroid escapes this only because it is thin-walled everywhere.
  Pattern: solid = `BaseCylinder().voxConstruct()`; thin features (barb ridges) = SDF `BoolAdd`
  (`MechanicalLock.cs`, the Ti-coin split). A `verify` solidity gate guards the regression.
- **`ImplicitRadialGyroid` is degenerate near r=0** (cylindrical singularity) — use a
  cartesian gyroid for small rods (still bicontinuous).
- **Gyroid `wallParam` is DIMENSIONLESS** (the gyroid eq ∈ [-1.5, 1.5]), not mm; a clean
  wall needs `wallParam ≪ amplitude`. **Porosity is voxel-dependent → MEASURE it** (a
  coarse voxel under-resolves voids → falsely high porosity).
- **Voxel-resolution floor:** sub-100 µm pores need voxel ~0.03 mm → huge grids. The Ø11
  anode renders cleanly at 0.1 mm (pores ~2.5 mm); realistic 300→100 µm pores are the
  HW.33 ceiling — and **un-printable at 65 %** anyway (SLM wall ~200 µm → min printable pore
  ≈ 1.2 mm; canonical 100 µm periphery would need a ~26 µm wall).
- **Continuous radial gradient distorts above ~0.8× period ratio:** a spatially-varying
  frequency makes the SDF non-Eikonal (`|∇eq| ∝ f`); the parasitic `∇f·coord` term collapses
  porosity (measured 67→42 % at period 2.5→1.3 mm). Keep continuous gradients gentle. For a
  STRONG pore contrast use `topology: stepped` (constant-period zones → distortion only at the
  thin boundary ring). A phase-correct strong continuous gradient needs period-tensor/conformal
  (Noyron/nTop-level), beyond this demo. **Per-shell porosity uses cumulative-diff** (thin rings
  under-count metal on distorted geometry).
- **`ImplicitUsings` must stay ENABLED** for `src/SilkenCad.Leap` (vendored LEAP source
  relies on implicit `using System` / `System.Collections.Generic`).
- **`out/` + `imgui.ini` are gitignored** (derived / viewer runtime). Native runtime
  lives in `~/.dotnet` → `export DOTNET_ROOT=$HOME/.dotnet` if running the apphost directly.
- **`render`/`section` need a display** (PicoGK native viewer): macOS desktop OK, headless
  CI = `Library.Go` SIGSEGV/139. The screenshot is **TGA** regardless of a `.png` name
  (`RequestScreenShot` is native) → convert TGA→PNG via `sips` (mac). The managed `Viewer`
  exposes `qOrientation` + view-cube presets (instance, not static) but NOT `SetViewAngles`/
  `RequestClose` (drop explicit camera → auto-frame; `bEndAppWithTask` exits). `ColorFloat`
  alpha does NOT show a rod through a dense gyroid → use `section` (cutaway) + a gold material.

## CI (enterprise 2-job)

`cad_smoke.yml` — path-gated on `tools/cad/**`:
- **`logic` (ubuntu)** — `dotnet build` + the full xUnit suite. The suite is PicoGK-runtime-free
  (CEM parse, gyroid/mate SDF math, connectivity flood-fill — no `Library.Go`), so it runs on a
  cheap fast Linux runner as the **HARD** regression gate.
- **`render` (macos-14)** — `dotnet build` (hard, both OSes) + `verify` golden-metrics (best-effort:
  `Library.Go` SIGSEGVs / exit 139 on the headless hosted runner — no Metal/display context,
  CI-confirmed 2026-06-20) + a CycloneDX SBOM + metrics artifacts.

Local `dotnet run -- verify` stays the PRIMARY metrics gate (`00_07` HW.1); a self-hosted
macOS-with-display runner would re-arm render-verify as a hard gate.

## Status & deferred

**v2 graded anode shipped** — three CEM-driven grading strategies, all MEASURED and FEA/bio-gated
(the "which is best" answer is open; the generator is unbiased, not opinionated):
- **continuous cell-size** (`GyroidPeriodRimMm`): gentle only (phase-distortion-limited ~0.8×) —
  flat porosity, smooth pore taper.
- **porosity gradient** (`GyroidWallParamRim`): clean monotone profile (the "softer rim").
- **stepped heterostructure** (`Topology: stepped`, `ZonedGyroid`): strong ~2× pore contrast at
  constant porosity. Own SDF, not LEAP `ImplicitModular` (`FunctionalScaleTrafo` is a hard-coded
  Z-demo + the LatticeLibrary submodule is ~1 yr stale).

5-SKU per-species sweep + a porosity-gradient demo + a stepped demo (7 SKU total).

**ARCH.25 connectivity (shipped)** — `Connectivity.cs` adds a two-phase topological audit
(open-pore↔Archimedes · percolation↔EAAE flow-through · solid-island↔AM/electrical · closed-pore↔trapped-powder · specific-surface
↔EBFC-area) as a fast display-less xUnit gate; `verify` adds open≥95% · solid-disc≤2% · percolate
axial+radial. Two-phase resolution: **pore** OK at the coarse step, **solid** needs ~period/24 (a coarse
grid fragments thin walls into false islands AND merges the sheet gyroid's two pore labyrinths — at
period/16 the island FRACTION already reads ≤0.3 % while the labyrinth COUNT is still wrong on every
period-graded species SKU; skill `picogk` gotcha #8). ⚠ That calibration is SHEET-era: since the
network verdict landed (2026-09-11) no shipped SKU has two labyrinths to merge, so the shipped set no
longer exercises the period/24 rule — its carrier is now a dedicated sheet-held pin (`picogk` #8).

**Mechanical-lock barbs (shipped)** — `MechanicalLock.cs` adds annular asymmetric **ratchet barbs** +
a **DIN-471 retaining groove** on the Ti shank (`01_01 §4.3 A/B`, HW.26 — the lock against PEEK
cold-flow creep): own SDF (4th, ratchet `R(z)`), solid `BaseCylinder` + thin barb-ridge `BoolAdd` +
groove-ring `BoolSubtract` + a central bore (`0` ⇒ SOLID monolithic anode shank, `01_01 §1.4`; `Ø1.35` ⇒
cathode channel the bus rod threads). Golden-metrics MEASURED off the profile (barb count /
height / base, groove depth) + a **self-support face angle** (Noyron manufacturing-awareness): the
ratchet self-supports at the `01_02 §1.6` tip-down / leading-ramp-down orientation (Ti64 LPBF 60°
downface, Sa≈15µm). Zone-1 Ø11 + Zone-3 placeholder Ø (HW.8 dim-freeze). Grounded over canon §4.3:
tooth over-spec resolved at h=0.28; DIN-471 groove = real shaft dims (was off-spec 0.8×0.6).

**Cathode flange / Деталь 3 (shipped)** — `cathode_flange` CEM → solid Ti flange Ø25 (frozen) reusing the
§4.3 lock for the barbed Zone-3 shank (`CathodeFlange.ShankCem` mapping, dir −1) + 3 radial **bayonet lugs**
(`LocalFrame(pos, radialZ)`) + Ø1.35 bus channel (the monolithic rod threads it) + O-ring groove. `verify` gates solidity (NOT hollow-shell,
gotcha #9), Ø25, lugs-fused (bbox extent past the rim — 3 lugs @120° are asymmetric → span ≈ flangeD +
protrusion), barb-count. Top face = pogo pads (coating, not geometry); side/perimeter = cathode catalytic
(O₂ ingress, 02_02 §1.2). **Деталь 4 radome v2c = next phase** (dome + shield bell + bayonet socket + cavity).

**Ti-coin A_electrode (shipped)** — `ti_coin` CEM → Ø16 disc, 1 face ≈ 2 cm² (01_03 §3.5); `verify` gates
the projected `active_electrode_area_cm2` (|A−2.0|≤0.1) + an optional `active_window_diameter_mm` (an
O-ring / lacquer defined-area cell — decouples A from the coin edge). Disc not square: RDE-ready, uniform
radial j, no corner edge-effects (01_01 §6.1).

**wallParam scan (shipped)** — `scan <anchor-cem>` sweeps the gyroid wall band → the CEM working window
(the wallParam range that stays printable + open-pore + percolating). 🔴 **The window is
TOPOLOGY-dependent, because the parameter changes meaning**: on sheet it is a band and pine reads
[0.80, 1.30] with 1.0 → 67.6 % mid-window; on the network branch we now ship it is a level, the measured
pine window is [−0.50, 0.60], and the working point is 0.10. The sweep bounds follow the CEM's topology
— they used to be fixed at [0.2, 1.8], which put the ratified network point OUTSIDE the sweep. Pure-
managed (no Library.Go), `WallScan.cs` under xUnit.

**Radome / Деталь 4 (shipped)** — `radome` CEM → hollow PEEK dome Ø25 (gotcha #9 INVERTED: the hollow IS
intended → the gate checks the wall, not solidity) + a rounded shield bell (≥3/R≥5, anti-overgrowth) +
bayonet socket (L-slot, mate the Деталь-3 lugs) + PCB cavity (⛔ its ≥12 floor is OURS on the CEM dim, NOT antenna↔Ti and NOT the canon ≥8 — 00_07 HW.33) + rim O-ring groove (⛔ RATIFIED AWAY 2026-09-10 and still cut: one groove belongs in the flange against a FLAT rim). `verify`
gates hollow-fraction / bell-rise / cavity / mate-fit. **🏁 Anchor-CAD family complete** (coin→anode-v2→
ARCH.25→barbs→Деталь3→Деталь4). ⚖️ MATE-Ø radial: RATIFIED 2026-09-10 — Ø25 stays, lugs go inboard, and a LOCAL INTERNAL RIM BOSS carries both the bayonet socket and the seal land; the enclosing `skirt` is WITHDRAWN because it cuts the lower cavity past the flange rim and so deletes the face the ratified O-ring seals against. The boss is not modelled yet (open leg); the bayonet-Z half is an open ⚖️, not bench work (00_07 HW.33).

**Capsule-end assembly / mate-audit (shipped)** — `Assembly.cs` + `anchor_assembly` CEM brings Деталь 3 ↔ Деталь 4
into one frame at the bayonet datum (radome lock-groove ↔ flange lugs) and MEASURES the residual mismatch (radial
−2.0 · bayonet-Z 6.42 · RF 8.0 mm) + models the two MATE-Ø candidates (`mate_strategy` skirt Ø30 vs inboard Ø25). ⚠️ The `RfClearanceMinMm = 12` it is judged against is the CEM's number, NOT canon: `02_01 §5.3` asks for `≥ 8` and calls 12 the outcome of a proposed board stack (00_07 HW.33, 2026-09-11).
An AUDIT table, NOT a part pass/fail — the mismatch is the real un-reconciled Z-stack (→ HW.17/HW.8), so `verify`
exits on a broken render only; the numbers are asserted by the pure xUnit suite (`AssemblyTests`). Reuses
`CathodeFlange.Build` · `Radome.Build` · `MeshUtility.voxApplyTransformation` (lift) · `BoolIntersect`. Z-stack
inputs mirror `tools/in_silico/scripts/52`. Canon `02_02 §4.4`.

**Zone-2 sleeve / Деталь 2 (shipped)** — `zone2_sleeve` CEM → plain hollow PEEK tube via `BasePipe` (bore Ø11 / OD
Ø15 wound / 50 mm, frozen `01_01 §1`). The simplest part: no barbs/grooves/hex — the smooth bore receives the Ti
shanks at 150 °C (hex anti-rotation `§4.3 C` is bench-gated → deferred). `verify` gates hollow + OD = bore+2·wall + length.

**Full axial stack / mate-audit (shipped)** — `AxialStack.cs` + `anchor_axial_stack` CEM brings ALL FOUR zones (anode
→ Zone-2 sleeve → flange → radome) into one axis and MEASURES the press-fit interfaces the capsule-end never touched:
**Zone1↔Zone2 = 0.00 mm line-to-line** (real +interference = the H7/s6 band on bench, ISO 286) · **Zone2↔Zone3 = −1.0 mm
= the Ø9-in-Ø11 clearance (F1, shank Ø placeholder → HW.8.9)** · insertion budget 6 mm · span 63 mm · bus continuous.
An AUDIT table like the capsule-end — render-sanity exit only, findings asserted by `AxialStackTests`. Render uses the
Zone-1 envelope (solid Ø11; a press-fit cares about OD, not porosity). The render overlap sleeve∩capsule (~8 mm³) is the
flange SHOULDER resting on the sleeve top face, NOT the shank (Ø9 floats in bore Ø11). Reuses `Zone1Anode.Envelope` ·
`Zone2Sleeve.Build` · `Assembly.Build` · `voxApplyTransformation` (Noyron Boolean multi-part). Canon `02_02 §4.5`.

**Monolithic bus rod (shipped, `01_01 §1.4` / HW.34)** — `bus_rod_diameter_mm` > 0 ⇒ `Zone1Anode.BuildMonolithic`
adds a SOLID central rod (`BusRod.voxConstruct()` `BoolAdd`, gotcha #9 — not the SDF ctor). ⚠️ **Fabrication-AGNOSTIC: «monolithic» is the RESULT, not the route — the ratified fabrication is a WELD** (`00_07` HW.34, 2026-09-10: an as-printed rod carries `ENDURANCE_OVER_YIELD × AS_PRINTED_DERATE`, a welded cold-drawn wire does not), so the rod arrives as bought wire plus a weld and its tolerance/`Sa` come from a wire spec canon does not carry. Porosity stays a property
of the gyroid (the rod is SDF-invisible → connectivity/porosity gates untouched), `verify` separately MEASURES the
fused rod. Full anode→cathode-channel→flange-pad through-rod; `AxialStack.BusRodClears` audits rod + 2·liner **<** channel — STRICT since 2026-09-11 (`00_07` HW.34): at `≤` the frozen trio `1.0 + 2×0.15 = 1.30` passed against a Ø1.30 bore, i.e. the gate blessed a ZERO nominal clearance — a true statement about the sum and a false one about the assembly. ⛔ Its declared ceiling did not change: it judges NOMINALS and a DIAMETER, so green here is not proof that a real pair mates, and it says nothing whatever about the liner's LENGTH or its ends. ⚠️ **That gap is no longer an open judgment: the axial extent was RATIFIED 2026-09-12** — the tube spans the whole Zone-3 channel, flush at both faces, captured at ONE end only (`01_01 §1.4`, `00_07` HW.34). The gate simply still cannot see it, so building the tube body and growing a Z check is now WORK, not a decision. What stays open is which end is fixed and whether the channel needs its own seal.

**Engineering drawings + render (shipped)** — `draw <cem>` → SVG (human) + **DXF via netDxf** (factory-native, opens
in AutoCAD/Fusion), pure-managed, consuming the CEM `ToleranceSpec`/`NotesSpec` (fits; GD&T datums;
coating-restriction; lattice-spec). §7/§8 DECIDED: DXF+SVG / ISO 1st-angle / CEM-tolerances.
⚠️ **«Fits as Lamé-µm, NOT a blind ISO-286 `H7/s6` on a PEEK bore» is the canon REQUIREMENT (`01_01 §4.2`), and this
line used to state it as if it were the shipped reality.** It is not: `cem/zone2_sleeve.json`'s 5–34 µm is the ISO 286
table (`tools/in_silico/lib/constants.py`), which Lamé consumes to compute a contact pressure rather than produces.
The generator briefly hid that by appending a hard-coded «(Lamé, E_PEEK-aware)» to the line — invented PROVENANCE on a
true value, removed — and the engineering verdict is open in `00_07` HW.3. **This tract prints QUANTITIES; where a
number came from is engineering text and belongs in the CEM.**
⛔ **The shipped-kind roster is `Program.Draw`'s `switch`, not this paragraph** — it carried one and went stale the day
a kind landed. Phasing, and the kinds deliberately NOT drawn with their grounds (today: the radome, because its
geometry holds two ratified-but-unapplied HW.33 verdicts), live in `docs/drawings_program.md §7`.
The NORM — why the drawing comes from the CEM and not the mesh, the two readers, the loud-absence rule, what the
acceptance contract must carry — is canon `01_02 §6`; `docs/drawings_program.md` stays the research + phase roster.
`render` / `section <cem>` → PicoGK native-viewer PNG (presentation gallery `docs/images/cad/`, rebuilt by
`scripts/render_gallery.sh`, NOT SSOT). ⚠️ **Not SSOT ≠ free to lag:** those SVGs are committed and open straight
from GitHub (blob-rendered), so they are the drawings an outsider actually reads — and nothing re-runs the script
for you. (⛔ `wiki:sync` does NOT carry them: it syncs canon `NN_NN_*.md` and copies an image only where a doc
EMBEDS it as `![…](…)`, and none does.) Touch `Drawing.cs` or a CEM ⇒ re-run it and commit the SVGs; `DrawingTests` reds if their CONTENT drifts
from the shipped manifests (ceiling: content + frame-fit, not byte-currency; the PNGs are pinned by nothing).
LEAP 71 ships metal engines WITHOUT 2D drawings — code is the engineering intent.

**Deferred:** the rim-boss implementation + the bayonet-Z reconcile (open ⚖️: the mismatch is t/2 + lockGrooveZ + gap, three positive terms, so the lug needs a Z of its own — `Assembly.RequiredLugZMm`; bench follows at HW.8.8) · the shank-Ø
press-fit reconcile (Ø9 → H7/s6 under bore Ø11, HW.8.9) · a phase-correct strong continuous gradient (period-tensor/
conformal) · Euler-χ / tortuosity connectivity cross-checks (ARCH.25 nice-to-have).

## License

Our code: AGPL-3.0 (repo `LICENSE`). Vendored: PicoGK (NuGet) + ShapeKernel +
LatticeLibrary — **Apache-2.0** (LEAP 71); see `/NOTICE`.
