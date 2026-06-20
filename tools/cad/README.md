# `tools/cad/` — SilkenNet Code-as-CAD (PicoGK)

The "set up once" home for the project's geometry surface — the CAD peer to
`tools/ml/` (ML), `tools/in_silico/` (chemistry), `contracts/` (Solidity),
`firmware/` (edge), and Rails (backend). A small, deterministic **Computational
Engineering Model (CEM)**: geometry is *computed from intent* in code + `cem/*.json`,
in the spirit of LEAP 71 **Noyron** — an algorithm, not generative ML.

> **Canon SSOT:** [`01_02 §6`](../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (PicoGK
> stack + Noyron methodology) · [`01_01 §5`](../../docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md)
> (anchor geometry) · tracker [`00_07` HW.1.PicoGK / HW.33](../../docs/00_07_Action_Plan_Tracker.md).
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
| `src/SilkenCad/Program.cs` | CLI: `smoke` / `build <cem>` / `verify <cem>` (headless `Library.Go`) · `scan <cem>` (wallParam window, pure) |
| `src/SilkenCad/TiCoin.cs` | Stage-2 in-vitro coupon — disc + eyelet (`01_01 §6.1`) |
| `src/SilkenCad/Zone1Anode.cs` | Zone-1 gyroid anode + the custom `CartesianGyroid` SDF |
| `src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity/bbox/tris) + LEAP `Measure.fGetSurfaceArea` |
| `src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + flood-fill (open/closed-pore, percolation, solid-island, specific-surface) |
| `src/SilkenCad/WallScan.cs` | wallParam critical-threshold scan → the CEM working window (printable + open-pore + percolating); pure-managed, no render |
| `src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` ratchet-barb + DIN-471 groove SDF on a hollow shank (Zone-1/Zone-3 demo) + self-support metric |
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

## CI (deferred — local-verify first)

The `verify` exit-code is CI-ready. First-party PicoGK = macOS / Win64 only (Linux =
community Docker + xvfb). A `cad_smoke.yml` on a macOS Apple-Silicon runner is the future
target (`00_07` HW.1.PicoGK).

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
(open-pore↔Archimedes · percolation↔EAAE flow-through · solid-island↔AM/electrical · specific-surface
↔EBFC-area) as a fast display-less xUnit gate; `verify` adds open≥95% · solid-disc≤2% · percolate
axial+radial. Two-phase resolution: **pore** OK at the coarse step, **solid** needs ~period/16 (a coarse
grid fragments thin walls into false islands — skill `picogk` gotcha #8). Feeds `00_07` HW.33 sheet-vs-network.

**Mechanical-lock barbs (shipped)** — `MechanicalLock.cs` adds annular asymmetric **ratchet barbs** +
a **DIN-471 retaining groove** on a hollow shank (`01_01 §4.3 A/B`, HW.26 — the lock against PEEK
cold-flow creep): own SDF (4th, ratchet `R(z)`), solid `BaseCylinder` + thin barb-ridge `BoolAdd` +
groove-ring `BoolSubtract` + Ø1.3 bus bore. Golden-metrics MEASURED off the profile (barb count /
height / base, groove depth) + a **self-support face angle** (Noyron manufacturing-awareness): the
ratchet self-supports at the `01_02 §1.6` tip-down / leading-ramp-down orientation (Ti64 LPBF 60°
downface, Sa≈15µm). Zone-1 Ø11 + Zone-3 placeholder Ø (HW.8 dim-freeze). Grounded over canon §4.3:
tooth over-spec resolved at h=0.28; DIN-471 groove = real shaft dims (was off-spec 0.8×0.6).

**Ti-coin A_electrode (shipped)** — `ti_coin` CEM → Ø16 disc, 1 face ≈ 2 cm² (01_03 §3.5); `verify` gates
the projected `active_electrode_area_cm2` (|A−2.0|≤0.1) + an optional `active_window_diameter_mm` (an
O-ring / lacquer defined-area cell — decouples A from the coin edge). Disc not square: RDE-ready, uniform
radial j, no corner edge-effects (01_01 §6.1).

**wallParam scan (shipped)** — `scan <anchor-cem>` sweeps the gyroid wall band → the CEM working window
(the wallParam range that stays printable + open-pore + percolating; pine: [0.80, 1.30], default 1.0 →
67.6 % mid-window). Pure-managed (no Library.Go), `WallScan.cs` + 3 xUnit; feeds HW.33 + the FEA
sheet-vs-network envelope.

**Deferred:** integrating shank+barbs into the full gyroid rod (separate session) · PEEK Radome ("шляпа",
HW.17) + cathode flange/PEEK Zone 2 as further PicoGK parts (blocked on HW.33 dim-freeze) ·
a phase-correct strong continuous gradient (period-tensor/conformal) · Euler-χ / tortuosity connectivity
cross-checks (ARCH.25 nice-to-have).

## License

Our code: AGPL-3.0 (repo `LICENSE`). Vendored: PicoGK (NuGet) + ShapeKernel +
LatticeLibrary — **Apache-2.0** (LEAP 71); see `/NOTICE`.
