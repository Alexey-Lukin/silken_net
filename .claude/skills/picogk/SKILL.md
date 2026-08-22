---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin in-vitro coupon, the Zone-1 gyroid anode, the CartesianGyroid SDF, the PEEK Radome — shipped, `dotnet run -- build cem/radome.json`) and the CEM (Computational Engineering Model) manifests that drive them. Knows the non-obvious gotchas — render lattices via `new Voxels(IImplicit, BBox3)` + BoolIntersect NOT voxBounding.voxIntersectImplicit (uncatchable native OpenVDB abort at fine voxel on thin bored parts), headless `Library.Go(voxel, task, bEndAppWithTask:true)` not the stale v1.6 `new Library()`, ImplicitRadialGyroid axis-singularity → cartesian gyroid, dimensionless gyroid wallParam + voxel-dependent porosity (MEASURE it), the voxel-resolution floor, ImplicitUsings-ENABLED for vendored LEAP source — and the local-verify discipline (`dotnet run -- verify` → metrics.json, exit 0/1). Routes to 01_02 §6 (PicoGK stack + Noyron methodology) + 01_01 §5 (anchor geometry) + tools/cad/README, does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"add the radial pore gradient\", \"build the Ti-coin STL\", \"set up the .NET CAD project\"."
---

# PicoGK Code-as-CAD (`tools/cad`)

Navigation aid + non-obvious gotchas. The **SSOT is the docs + code + `tools/cad/README.md`
below** — this skill points, it does not restate (so it can't drift). Verify a fact at its
home before trusting a summary. Methodology (per LEAP 71 Noyron): a CEM is a *deterministic
algorithm*, not generative ML — an agent writes the generator, the generator computes the geometry.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|----------------|
| `tools/cad/README.md` | Operational home: layout, local-verify recipe, the FULL gotcha list, license |
| `docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md §6` | PicoGK stack (.NET 9, PicoGK 2.2 NuGet + ShapeKernel/LatticeLibrary submodules), Noyron methodology, real API, honest caveats |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §5/§6` | Anchor geometry: gyroid 65% porosity, pore gradient 300→100µm, Gibson-Ashby isoelasticity, Ti-coin Stage-2 coupon (A=2cm²+eyelet) |
| `docs/00_07_Action_Plan_Tracker.md` HW.1 / **HW.33** | Build state + the anchor geometry audit (founder decisions: radial gyroid (б), Ø11; open gaps: PEEK/hole chain, FEA) |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §6` | Cross-biome 5-SKU (pine/oak/broadleaf/mangrove/tropical) |
| `docs/00_03_TRL_Matrix_HIL_and_Beyond.md §3.6` | Code-as-CAD vs generative-AI; In-Silico for the Hardware stream |
| `tools/cad/docs/drawings_program.md` | Engineering-drawing program: CEM-native DXF (netDxf) + SVG, the ASME-Y14.5≠projection fix, lattice-as-inspection-card, phased §7 rollout |
| `extern/.../README_ImplicitLibrary.md` | LEAP's own implicit/TPMS guide (splitting logic, modular workflow for the graded v2) |

## Source Files

| File | Role |
|------|------|
| `tools/cad/cem/*.json` | CEM manifests — the Git-SSOT parameter inputs (`kind` discriminator: `ti_coin`, `anchor_zone1`, `mechanical_lock`, `cathode_flange`, `radome`, `zone2_sleeve`, `anchor_assembly`, `anchor_axial_stack`) |
| `tools/cad/src/SilkenCad/Program.cs` | CLI dispatch (`smoke`/`build`/`verify`/`scan`/`draw`/`render`/`section`) + `RunHeadless` (the `Library.Go` wrapper); `draw` is pure-managed (no Library.Go), `render`/`section` drive the native viewer |
| `tools/cad/src/SilkenCad/Cem.cs` | CEM records + JSON parse (snake_case). Engineering-drawing PMI lives here: optional `ToleranceSpec` (fits / Lamé-µm / GD&T datums) + `NotesSpec` (material/process/**post-process**/surface/coating-restriction/lattice-spec/inspection) on each part record — Noyron-native SSOT, fed to `draw` |
| `tools/cad/src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw <cem>`): **SVG (human) + DXF via netDxf (CAD-native factory deliverable, opens in AutoCAD/Fusion)** — no PDF (never built; `drawings_program §3`). Pure-managed string/entity build, no Library.Go. Consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). Shipped kinds = `ti_coin` + `cathode_flange` (§7 rest deferred — `tools/cad/docs/drawings_program.md`). ⚠️ gotcha #11 |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) + reuses LEAP `Measure.fGetSurfaceArea` |
| `tools/cad/src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-conn flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit |
| `tools/cad/src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb + DIN-471 groove SDF on the shank (Zone-1 solid monolithic / Zone-3 channelled); render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `tools/cad/src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + O-ring groove |
| `tools/cad/src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + bayonet socket + PCB cavity + O-ring groove (gotcha #9 INVERTED — hollow is intended) |
| `tools/cad/src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, `02_02 §4.4`) — bayonet datum via `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates; pure mate-math (xUnit) + render interference (`verify`) |
| `tools/cad/src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (smooth bore; hex + flange-shoulder deferred, bench-gated) |
| `tools/cad/src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, `02_02 §4.5`) — press-fit interference + insertion budget + span; reuses `Assembly.Build` + Zone-1 envelope; pure mate-math (xUnit) + render (`verify`) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts + porosity drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify`.

**State** (what is built / open ⚖️ / curator lessons) lives in memory, not here: `[[project_picogk_code_as_cad]]` · `[[project_bus_monolithic_onehome]]` (bus topology + the PEEK-liner trap below) · `[[project_coin_bakeoff_trl4]]` (the Ti-coin keystone this CAD feeds). This pointer was **missing** until 2026-08-08 — every sibling skill (`ssot-maintenance`, `ml-engineering`, `web3-pipeline`) carried one and this file did not, so CAD state was reachable only by someone who already knew it existed.

## Gotchas Not Obvious From Docs

0. 🔴 **`tools/cad/cem/*.json` is the parameter SSOT — but `cathode_flange.json` hard-codes a branch that is NOT decided, so do NOT "fix" the manifest.** Its `liner 0.15 mm` (with the Ø1.0 rod through a Ø1.3 channel) reads as if the PEEK-lining branch were settled; [`01_01 §1.4`](../../../docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md) says the implementation is still **open** (⚖️ HW.34 — Parylene ~10 µm and TiO₂ ~0.1–10 µm cannot reach 0.15 mm, so the frozen number silently elects PEEK). The contradiction is in the CANON PROSE and must be fixed there first; patching the JSON to match a different branch breaks the `AxialStack.BusRodClears` F3 gate (rod + 2×liner ≤ channel). The number lives in canon and the manifest, but the *warning* had no git home at all until now — JSON carries no comments, and a future tidy-up pass reads a frozen value as a decision.

1. **Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`** — NOT
   `voxBounding.voxIntersectImplicit(impl)`. The convenience method yields a malformed
   (background-0) OpenVDB level set at fine voxel on a thin bored part → an **uncatchable
   native abort** (`libc++abi … ValueError: expected grid A outside value > 0, got 0` — a
   process kill, not a .NET exception). The ctor path runs at 0.1mm; voxIntersect's ceiling
   was ~0.4mm. (`Zone1Anode.Anode`.)
2. **`ImplicitRadialGyroid` is degenerate near r=0** (cylindrical singularity) — fine for
   large annular parts, empty grid for a small rod near its own axis. Use a **cartesian
   gyroid** (uniform everywhere, still bicontinuous → honors founder decision (б), HW.33).
3. **Headless = `Library.Go(voxel, task, bEndAppWithTask:true)`**, not `new Library()`
   (the v1.6 headless pattern → "relies on Library::Go" abort in v2.2). It briefly inits a
   Metal/GL viewer then closes with the task — so CI needs a display (macOS runner / xvfb).
4. **Gyroid `wallParam` is DIMENSIONLESS** (gyroid eq ∈ [-1.5, 1.5]), not mm: `|eq| <
   0.5*wallParam` ⇒ solid; a clean wall needs `wallParam ≪ amplitude`. **Porosity is
   voxel-dependent → MEASURE it** (a coarse voxel under-resolves voids → falsely high
   porosity; at 0.1mm the Ø11 anode reads 67.6% ≈ the 65% target, vs 21–28% at 0.4–0.5mm).
5. **Voxel-resolution floor + gradient distortion** — sub-100µm pores need voxel ~0.03mm →
   ~10⁹-voxel grids. The Ø11 anode renders cleanly at 0.1mm (pores ~2.5mm); realistic 300→100µm
   pores are the HW.33 ceiling (and **un-printable at 65%**: SLM wall ~200µm → min pore ~1.2mm).
   Separately, a **continuous radial gradient distorts above ~0.8× period ratio** (non-Eikonal
   `|∇eq|∝f`; the `∇f·coord` term collapses porosity 67→42% at 2.5→1.3mm) → keep continuous gentle,
   or use `ZonedGyroid` (stepped) for strong contrast. Per-shell porosity = cumulative-diff (thin
   rings under-count metal on distorted geometry).
6. **`ImplicitUsings` ENABLED for `src/SilkenCad.Leap`** — vendored LEAP source relies on
   implicit `using System` / `System.Collections.Generic`. Disabling → 200+ CS0246. Strict
   knobs (warnings-as-errors, nullable) are ON for OUR code (`src/SilkenCad`, `tests/`), OFF
   for the vendored project (mirrors the `firmware/extern` vs `firmware/common` split).
7. **`DOTNET_ROOT=$HOME/.dotnet`** if the apphost binary is run directly (native runtime is
   in the non-standard `~/.dotnet` install → `libhostfxr.dylib not found` otherwise);
   `dotnet run` is unaffected.
8. **Connectivity needs WALL-resolution, not pore-resolution** (`Connectivity.cs`, ARCH.25) —
   the gyroid wall is only ~period/10 thick; sampling the SDF coarser than ~wall/2 fragments thin
   walls into **false** solid "islands" (measured 24–61% disconnected at 0.3mm → ~0% at period/16).
   Pore-phase metrics (open/percolation) are fine at any step → `SampleAnchor` ties the step to the
   finest period. And a **sheet** gyroid is tricontinuous → `PoreClusterCount`==2 is a topology FACT,
   not a defect (don't gate on it). NB `Ex_ImplicitGyroidGenus` is **misleading** (renders a gyroid on
   a genus-torus shape; computes no genus) — LEAP exposes no connectivity, but `Measure.fGetSurfaceArea`
   (surface) + `fGetVolume` exist and are reused, not re-implemented.
9. **A FILLED (solid) body must come from ShapeKernel `voxConstruct`, NOT `new Voxels(IImplicit, BBox3)`.**
   The SDF ctor builds a **narrow-band** field (voxels near the surface only), so a solid core falls
   *outside* the band and renders as a **hollow shell** (`MechanicalLock.cs`: a Ø11 shank measured
   ~17 mm³ vs ~1700 expected). The gyroid dodges this only because it is thin-walled everywhere.
   Pattern: solid = `BaseCylinder().voxConstruct()`; thin features (barb ridges) = SDF `BoolAdd` (the
   Ti-coin split). The `verify` solidity gate (volume > 0.8·annulus) guards the regression.
10. **`render`/`section` (presentation) need a display + the screenshot is TGA.** The PicoGK native
    viewer (`Library.oViewer()…RequestScreenShot` inside `Library.Go`) renders only with a display
    (macOS desktop OK; headless CI = `Library.Go` SIGSEGV/139). The frame is **TGA** regardless of a
    `.png` name → convert TGA→PNG via `sips` (mac). The managed `Viewer` exposes `qOrientation` +
    view-cube presets (instance, not static) but NOT `SetViewAngles`/`RequestClose` (drop explicit
    camera → auto-frame; `bEndAppWithTask` exits). `ColorFloat` alpha does NOT show a rod through a
    dense gyroid → use `section` (cutaway) + a gold material.
11. 🔴 **The drawing tract SILENTLY invents and silently drops — and the reviewer sees LESS than the
    factory** (deep-dig 2026-07-16; the `topology: "sheet"` default below is ONE MEMBER of this class,
    not a one-off).
    - **Silent drop:** `Drawing.NotesLines` → `void Add(label, v) { if (!string.IsNullOrWhiteSpace(v)) … }`
      — a null CEM field removes the whole line. There is no empty `Post-process: ___` for the shop to
      query; the drawing looks COMPLETE. Same for `ToleranceLines`: `Feature` renders only if Plus **or**
      Minus exists (`cathode_flange.json`'s `shank_dia` is absent from BOTH svg and dxf **today**), and
      `InterferenceMin/Max` need BOTH or both vanish.
    - **Silent invention (worse):** the fallbacks are unmarked defaults, so a missing field becomes a
      FABRICATED factory instruction — `?? "Ti-6Al-4V"` / `?? "SLM/DMLS"` (title-block) stamp the 4V
      baseline onto a Ta/Au/7Nb/CP-Ti coupon; the `Notes == null` branch prints "Ti-6Al-4V (**Grade 5**)"
      outright; `N(t.PlusMm ?? 0)` renders `"bore: 0.1/0 mm"` — a **zero minus-tolerance the CEM never
      stated**, in PMI, in the DXF. `CAD_REV ?? "local"` stamps `rev local` → zero git traceability.
    - **Reviewer < factory (inverted risk):** the SVG title-block truncates (`CathodeFlange`, PROCESS →
      22 chars) and overflows its canvas (TiCoin title-block writes past x=820 → PROCESS clipped
      mid-word; the SSOT line sits at y=566 on a 560-tall frame = invisible); the **DXF truncates
      nothing**. So a bad note rides to the shop precisely because self-review can't see it.
    - **Tests protect the bug:** every xUnit CEM is an INLINE literal — **not one test reads a shipped
      `cem/*.json`** — and `DrawingTests` asserts `Contains("Ti-6Al-4V", svg)` on a `Notes == null` coin,
      i.e. it green-lights the fallback that IS the defect. CI never runs `draw` on a real CEM
      (`cad_smoke.yml` runs `verify` only). The one test worth writing: read the real `cem/ti_coin.*.json`
      and assert every non-empty field appears VERBATIM in the DXF.
    Reflex when touching `Drawing.cs`/CEM: ask "what does a NULL here print on a factory drawing?" —
    and prefer a loud `NOT SPECIFIED IN CEM` over a plausible default.

## Common Tasks

- **Add a part / per-species SKU**: write `cem/<name>.json` (with a `kind`) + a generator in
  `src/SilkenCad/` + wire the `build`/`verify` switch in `Program.cs`; `dotnet run -- verify`.
- **Change anchor geometry**: edit `cem/anchor_zone1.*.json` (Ø, bore, period, wallParam).
  Geometry numbers are owned in `01_01 §5` + founder decisions in `00_07 HW.33`; **MEASURE
  porosity after** (gotcha #4). Render via `Zone1Anode.Anode` (the ctor route, gotcha #1).
  🔴 **`topology` defaults to `"sheet"` SILENTLY** (`Cem.cs`; a member of gotcha #11's class) and 6/7 `anchor_zone1.*` omit the key —
  so every SKU renders sheet, while canon `01_01 §5.5` says "дані схиляють до **network**". That choice
  is an un-made founder verdict (`00_07 HW.33` ⚖️), not a default to inherit: a factory STL cut today
  would ship the disfavored branch. Do NOT quietly pick a side when touching these manifests.
  (`stepped` is a separate, already-decided THIRD branch — implemented `ZonedGyroid`, orthogonal to the
  open sheet-vs-network verdict; `Cem.cs` now documents all three.)
- **Monolithic bus rod (`01_01 §1.4`, HW.34, SHIPPED)**: `bus_rod_diameter_mm` > 0 ⇒ a SOLID central
  rod core. `Zone1Anode.BuildMonolithic` = `Anode` (gyroid, ctor) **+ `BoolAdd(BusRod.voxConstruct())`**
  (solid via voxConstruct, gotcha #9 — NOT the SDF ctor). 🔑 **Porosity stays a property of the gyroid**
  (`Anode` + the annulus envelope, `InnerRadiusMm` = rod surface) — the rod is SDF-invisible, so connectivity
  /porosity gates are untouched; `verify` separately MEASURES the fused rod volume (`ReportAnchor`, ≳π(r)²·L).
  Cathode keeps its channel (`mechanical_lock.zone3`/flange bore); anode shank `bore→0` (solid). F3 audit =
  `AxialStack.BusRodClears` (rod + 2·liner ≤ channel).
- **Graded gyroid (v2, SHIPPED)**: own SDF, **NOT** LEAP `ImplicitModular` (`FunctionalScaleTrafo`
  is a hard-coded Z-demo, not radial; LatticeLibrary submodule ~1 yr stale). Three CEM-driven axes
  in `Zone1Anode`: `GradedCartesianGyroid` (continuous period+wall taper) + `ZonedGyroid` (stepped
  zones). Pick by goal — continuous-gentle (smooth, ≤~0.8× period ratio), `GyroidWallParamRim`
  porosity gradient, or `topology: stepped` for a STRONG ~2× pore contrast. **MEASURE** porosity.
- **Mechanical-lock barbs (`MechanicalLock.cs`, SHIPPED)**: asymmetric ratchet `R(z)` on the Ti shank
  — solid `BaseCylinder().voxConstruct()` + thin barb-ridge `BoolAdd` + groove-ring `BoolSubtract` + a
  central bore (`0` ⇒ SOLID monolithic anode shank, `01_01 §1.4`; `Ø1.3` ⇒ the cathode channel the bus rod
  threads) (gotcha #9 — never the SDF ctor for the solid). Tooth is over-specified in `01_01 §4.3` → keep
  α/β + h, DERIVE base = h·(cotα+cotβ), MEASURE in `verify`. Self-support is orientation-conditional (print
  leading-ramp-down, `01_02 §1.6`); DIN-471 groove = real shaft dims (not the off-spec canon 0.8×0.6).
- **Connectivity / validation (ARCH.25)**: `Connectivity.cs` samples the CEM SDF → 3-phase grid →
  6-conn flood-fill → open-pore (Archimedes) / percolation (EAAE flow-through) / solid-island (AM +
  electrical) / closed-pore (trapped-powder) / specific-surface. Pure-managed → fast display-less xUnit. Two-phase resolution split:
  **pore** OK at the coarse step, **solid** needs ~period/16 (gotcha #8). The `verify` gate adds
  open≥95% · solid-disc≤2% · percolate axial+radial. Feeds HW.33 sheet-vs-network (topology-agnostic).
- **Capsule-end assembly (`Assembly.cs`, SHIPPED)**: brings Деталь 3 ↔ Деталь 4 into one frame at the
  bayonet datum (radome lock-groove ↔ flange lugs) via `MeshUtility.voxApplyTransformation` (lift; the
  per-part `Build`s stay untouched) and MEASURES the residual mismatch (radial / bayonet-Z / RF) + models
  the skirt/inboard MATE-Ø candidates. An AUDIT table — `verify` exits on a broken render only; the
  mismatch numbers are asserted by pure xUnit. Canon `02_02 §4.4`; reconcile is 👤 bench (HW.17/HW.8).
- **Full axial stack (`AxialStack.cs`, SHIPPED)**: the SECOND integration artifact — brings ALL FOUR zones
  (anode → Zone-2 sleeve → flange → radome) into one axis and MEASURES the **press-fit** interfaces the
  capsule-end never touched: Zone1↔2 line-to-line (real +interference = H7/s6 band on bench) · **Zone2↔3 =
  −1.0 mm = the Ø9-in-Ø11 clearance = F1, shank Ø placeholder → HW.8.9** · insertion budget · span. AUDIT
  table; render uses the Zone-1 **envelope** (solid Ø11 — a press-fit cares about OD, not porosity; also
  keeps the 0.2 mm voxel safe). Reuses `Assembly.Build` + `voxApplyTransformation`. Canon `02_02 §4.5`.
  🔑 **`BasePipe`/`BaseCylinder` Z-origin = `[0, L]` from the frame** (grows along +localZ; verified in LEAP
  `Frames.cs` — NOT centred), so stack lifts are absolute; the render overlap sleeve∩capsule is the flange
  SHOULDER on the sleeve top face, not the shank (the Ø9 floats in the bore).
- **Generate an engineering drawing (`Drawing.cs` / `draw`, SHIPPED Phase 0+1)**: `draw <cem>` emits
  **SVG (human) + DXF via netDxf (factory, opens in AutoCAD/Fusion)** — no PDF (scoped in research, never
  built); ⚠️ read gotcha #11 BEFORE touching notes/tolerances — pure-managed, no Library.Go,
  consuming the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text; `DrawingStandard` ISO/ASME
  param). Drawing carries fits (Lamé-µm, NOT a blind ISO-286 metal `H7/s6` on a PEEK bore), GD&T datums,
  post-process + coating-restriction notes, lattice-spec. Shipped kinds = **`ti_coin` (Phase 1) +
  `cathode_flange` (Phase 2, rode the Ø25 freeze)** — flange has NO xUnit yet while Ti-coin carries five.
  Still deferred: Zone-2 sleeve, radome, **`draw anchor_zone1`** (gyroid inspection-card — does NOT exist,
  so the Zone-1 coating-restriction map has no carrier yet), assemblies. Home: `tools/cad/docs/drawings_program.md`.
- **Render / section for presentation (`render`/`section`, SHIPPED)**: `render <cem>` = a PicoGK native-viewer
  screenshot (gold Ti-metallic material); `section <cem>` = a −X cutaway (shows the bus rod through a dense gyroid
  where `ColorFloat` alpha can't). Display-gated (gotcha #10); output → `out/*.png` (native TGA → `sips`). The
  presentation gallery `docs/images/cad/` is NOT SSOT (`tools/cad/scripts/render_gallery.sh` rebuilds it).
- **Local-verify**: `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1) → `dotnet run -- draw cem/<x>.json` (SVG+DXF → out/)
  → `dotnet test`. CI = enterprise 2-job `cad_smoke.yml` (logic = Linux pure-xUnit hard [incl. draw/DXF]
  + render = macOS build-hard + verify best-effort, Library.Go 139 headless).
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink (vendored LEAP source, kept out of owned code).
