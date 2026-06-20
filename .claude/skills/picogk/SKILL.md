---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin in-vitro coupon, the Zone-1 gyroid anode, the CartesianGyroid SDF, future PEEK Radome) and the CEM (Computational Engineering Model) manifests that drive them. Knows the non-obvious gotchas — render lattices via `new Voxels(IImplicit, BBox3)` + BoolIntersect NOT voxBounding.voxIntersectImplicit (uncatchable native OpenVDB abort at fine voxel on thin bored parts), headless `Library.Go(voxel, task, bEndAppWithTask:true)` not the stale v1.6 `new Library()`, ImplicitRadialGyroid axis-singularity → cartesian gyroid, dimensionless gyroid wallParam + voxel-dependent porosity (MEASURE it), the voxel-resolution floor, ImplicitUsings-ENABLED for vendored LEAP source — and the local-verify discipline (`dotnet run -- verify` → metrics.json, exit 0/1). Routes to 01_02 §6 (PicoGK stack + Noyron methodology) + 01_01 §5 (anchor geometry) + tools/cad/README, does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"add the radial pore gradient\", \"build the Ti-coin STL\", \"set up the .NET CAD project\"."
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
| `docs/00_07_Action_Plan_Tracker.md` HW.1.PicoGK / **HW.33** | Build state + the anchor geometry audit (founder decisions: radial gyroid (б), Ø11; open gaps: PEEK/hole chain, FEA) |
| `docs/00_08_Beyond_TRL9_Planetary_Roadmap.md §1.3` | Cross-biome 5-SKU (pine/oak/broadleaf/mangrove/tropical) |
| `docs/00_02_AI_Native_Engineering_and_TRL.md §4a` | Code-as-CAD vs generative-AI; In-Silico for the Hardware stream |
| `extern/.../README_ImplicitLibrary.md` | LEAP's own implicit/TPMS guide (splitting logic, modular workflow for the graded v2) |

## Source Files

| File | Role |
|------|------|
| `tools/cad/cem/*.json` | CEM manifests — the Git-SSOT parameter inputs (`kind` discriminator: `ti_coin`, `anchor_zone1`) |
| `tools/cad/src/SilkenCad/Program.cs` | CLI dispatch (`smoke`/`build`/`verify`) + `RunHeadless` (the `Library.Go` wrapper) |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts + porosity drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify`.

## Gotchas Not Obvious From Docs

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
5. **Voxel-resolution floor** — sub-100µm pores need voxel ~0.03mm → ~10⁹-voxel grids. The
   Ø11 anode renders cleanly at 0.1mm (pores ~2.5mm); realistic 300→100µm pores are the
   HW.33 ceiling (may need a tiled/per-cell approach — or keep nTop — for fine pores).
6. **`ImplicitUsings` ENABLED for `src/SilkenCad.Leap`** — vendored LEAP source relies on
   implicit `using System` / `System.Collections.Generic`. Disabling → 200+ CS0246. Strict
   knobs (warnings-as-errors, nullable) are ON for OUR code (`src/SilkenCad`, `tests/`), OFF
   for the vendored project (mirrors the `firmware/extern` vs `firmware/common` split).
7. **`DOTNET_ROOT=$HOME/.dotnet`** if the apphost binary is run directly (native runtime is
   in the non-standard `~/.dotnet` install → `libhostfxr.dylib not found` otherwise);
   `dotnet run` is unaffected.

## Common Tasks

- **Add a part / per-species SKU**: write `cem/<name>.json` (with a `kind`) + a generator in
  `src/SilkenCad/` + wire the `build`/`verify` switch in `Program.cs`; `dotnet run -- verify`.
- **Change anchor geometry**: edit `cem/anchor_zone1.*.json` (Ø, bore, period, wallParam).
  Geometry numbers are owned in `01_01 §5` + founder decisions in `00_07 HW.33`; **MEASURE
  porosity after** (gotcha #4). Render via `Zone1Anode.Anode` (the ctor route, gotcha #1).
- **Graded gyroid (v2)**: `ImplicitModular(IBeamThickness, ICoordinateTrafo, IRawTPMSPattern,
  ISplittingLogic)` — `FunctionalScaleTrafo` for the radial 300→100µm cell-size gradient,
  `IBeamThickness` to hold ~65% porosity while the cell varies. See `README_ImplicitLibrary.md`.
- **Local-verify**: `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1). This is the gate (CI-ready, macOS-runner deferred).
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink; it stays
  out of the GitNexus graph (`.gitnexusignore` excludes `tools/cad/extern/`).
