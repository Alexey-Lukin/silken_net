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
                                                   (porosity, bbox, tris — measured metrics)
```

An agent **writes the generator** (reviewable `.cs`); the generator **computes the
geometry** deterministically. Parity is on derived metrics, never the raw STL bytes.

## Layout

| Path | What |
|---|---|
| `cache/fea/` | **COMMITTED** voxel-FE results (unlike `out/`, which is gitignored) — the numbers canon `01_01 §5.2` quotes. A `fea` run therefore has a diff, **and since 2026-09-12 that diff is a CI event**: `ruby scripts/fea_canon_sync.rb` (HARD in `docs.yml`) compares these files cell-by-cell against §5.2, so a re-measurement that moves a quoted digit must carry the canon edit in the SAME commit. The families: `<cem>.json` (apparent stiffness) ⊥ `size_effect_ladder.*` ⊥ `gibson_ashby_fit.*` (the fitted `C`/`n`) ⊥ `dilation_sensitivity.*` (face-offset sensitivity) ⊥ `periodic_homogenization.*` (the lattice's effective tensor and field — one file per topology · wall · cell count, its rows the steps ladder; pin `Periodic_Cache_Names_Carry_Topology_Wall_And_Cells_And_Never_Land_On_Another_Family`; the period and the field angles are held by `fea_canon_sync`, not the name). The fits are **per-resolution by filename on purpose** — one shared file would hold only the last run, so most quoted rows could not be confirmed by construction — and the dilation family goes one further, **one file per ROW**, named by element · offset · step · rod, so no run can land on another row or on a pinned file (pin `Dilation_Cache_Names_Never_Land_On_A_Pinned_File_Or_On_Each_Other`) |
| `cem/*.json` | CEM manifests (Git-SSOT inputs) — e.g. `ti_coin`, `anchor_zone1.pine`; one `kind` discriminator per manifest — each kind is a record in `Cem.cs`, dispatched in `Program.cs` |
| `src/SilkenCad/Program.cs` | CLI dispatch — ⛔ the verb roster is the `switch` in `Main`, never a list here (⚖️ founder 2026-10-17, DOC-T.123 — the list that stood here had gone stale); `dotnet run --project src/SilkenCad -- help` prints its human copy, kept beside it. `smoke` · `build` · `verify` · `probe` run headless through `RunHeadless` (the `Library.Go` wrapper); `draw` · `scan` · `fea` · `build-record` are pure-managed; `render`/`section` drive the native viewer. Per-verb recipes and traps live with the work: picogk `tasks.md` (`draw --vendor` — the vendor form, `docs/drawings_program.md` §8 item 5 · `fea --sweep`/`--ladder`/`--fit`/`--dilate` · `converge` · `render`/`section`), and gotcha #14 for `fea --fit` (a quoted row reproduces only with its FULL flag set) |
| `src/SilkenCad/Cem.cs` | CEM records + JSON parse (snake_case). Engineering-drawing PMI lives here: optional `ToleranceSpec` (fits / interference µm / GD&T datums / a LIST of `Features` — a named feature with NO limits still renders, as loud absence) + `NotesSpec` (material/process/**post-process**/surface/coating-restriction/lattice-spec/inspection) on each part record — Noyron-native SSOT, fed to `draw` |
| `src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw`): SVG (human) + DXF via netDxf (factory, opens in AutoCAD/Fusion); no PDF (never built — `docs/drawings_program.md` §3). Pure-managed; consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). Each kind is a `Drawing.X` + `Drawing.XDxf` pair — the roster and the add-a-kind checklist live in picogk `tasks.md` «Generate an engineering drawing»; an absent field prints loud (picogk #11). ⚠️ The SVG has a `viewBox` and therefore CLIPS; the DXF has no viewport and clips nothing — so a layout defect here always reads «reviewer sees LESS than the factory». The three symptoms of that (silent 22-char title-block truncation · title block drawn past the canvas · unwrapped notes running off the frame) are FIXED: truncation is announced (`… → NOTES` / `… → FOOTER`), notes word-WRAP, and the canvas height is COMPUTED from content. The rule survives the fix — check any notes/title-block change in BOTH readers |
| `src/SilkenCad/TiCoin.cs` | Stage-2 in-vitro coupon — disc + eyelet (`01_01 §6.1`) |
| `src/SilkenCad/Zone1Anode.cs` | Zone-1 gyroid anode + the custom `CartesianGyroid` SDF |
| `src/SilkenCad/Validation.cs` | measured metrics via `Voxels.CalculateProperties` (porosity/bbox/tris; porosity needs an envelope reference) + LEAP `Measure.fGetSurfaceArea`. ⚠️ These used to be called «golden-metrics» here, and since 2026-09-12 that word means something ELSE in this tree — see `Golden.cs` |
| `src/SilkenCad/Golden.cs` | committed REGRESSION baseline (`00_07` HW.33/HW.49): each `cem/anchor_zone1.*.json` has a sibling `*.golden.json` (six metrics, per-field tolerances) that `verify` compares and FAILS on. ⛔ Voxel-specific — a run at another voxel is not compared; pins regression, never correctness; an absent baseline is silence, not a pass. Write one only with `verify <cem> --write-golden` (the writer prints what moved), as a reviewed diff |
| `src/SilkenCad/BuildRecord.cs` | **build-record of ONE batch** (`CAD_REV=$(git rev-parse HEAD) dotnet run --project src/SilkenCad -- build-record cem/<a>.json … > <batch>.json`, schema `silkennet.build_record/2`, `01_02 §6`, `00_07` HW.51): commit (`CAD_REV` — declared, not verified) + each manifest's `cem_sha256` (`Cem.ReadWithSha256`, the bytes-hash the sheet prints) + the committed golden metrics (same grid only, `Golden.SameGrid`) + PicoGK version; the vendor fields are generated EMPTY and typed in from the order — the batch's vendor and number once, and per manifest (= per SKU; in the coin bake-off, per alloy) a list of builds (`vendor.parts[].builds[]`: coupon serial range · build · date · powder lot · certificate), one entry per build × powder lot. STDOUT, not `out/` (gitignored, gate-blind — picogk #17). ⛔ `golden_metrics` is the MODEL's baseline, never the printed batch; every machine-side `null` carries its reason in `absent_because` (picogk #11), a kind with no `*.golden.json` included |
| `src/SilkenCad/Probe.cs` | falsifiable probes of PicoGK-kernel BELIEFS (`probe <voxel-mm>`; picogk #1 · #9) — probe B can kill the process by design, so A runs first. Permanent on purpose: a belief about someone else's kernel that nothing re-runs survives their next release. Measured 2026-09-12 — the fine-voxel abort is an `int` truncation of the band width (0.34 mm lives, 0.33 dies), and the SDF ctor renders a CLOSED solid at 99.7 % |
| `src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-connected flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit. Also the MESH SOURCE for `VoxelFea`: `SampleRegion` (with a phase-override hook both FE callers leave null) and `LargestComponentMask` (membership, which `Components` does not keep; `bPeriodic` glues each face to its opposite for the periodic case's torus) |
| `src/SilkenCad/CellShape.cs` | Cell SHAPE of a lattice by height × radius (`00_07` HW.33) — the line-intercept fabric: crossing density along probe lines through the field, its quadratic-form fit, principal stretches against a constant-period nominal (`Nominal`, `PeriodAtMm` — the generator's own map, one home for both the `cellshape` verb and its pins); `GradedJacobian` is the first-order phase-map prediction; two EXPERIMENT fields for the HW.33 verdict (`AxiallyShiftedField`, `InPlaneGradedGyroid`), never the product generator |
| `src/SilkenCad/TopologyCrossChecks.cs` | ARCH.25 third phase — Euler-χ / tortuosity / as-printed cross-checks, INFORMATIONAL `verify` lines, not the `VERIFY OK/FAILED` gate (picogk #12); also the home of the lattice-thickness constants (`SheetThicknessPerPeriod` / `NetworkThicknessPerPeriod`, `LatticeThicknessMm`) that `Resolution` reads (picogk #5) |
| `src/SilkenCad/VoxelFea.cs` | voxel finite-element elasticity (`fea`, `00_07` HW.51/HW.33) — trilinear hexes on the Connectivity grid, matrix-free element-by-element, 8-colour parallel, Jacobi-CG; apparent stiffness in units of `E_solid`. ⛔ The mesh takes only the largest face-connected body (a floating island is a rigid-body mode); what it drops is reported. Two families of cases: a FINITE specimen loaded through its boundary (axial · radial — the part and the cube) ⊥ ONE PERIOD CELL under periodic conditions (`fea --periodic`, `00_07` HW.23) — the lattice's effective tensor, C44 included, and its ligament stress field under a uniaxial macro stress, a MATERIAL property and never the part's. Declared ceilings in the class header (one per family); numbers — `01_01 §5.2`, cache `cache/fea/` |
| `src/SilkenCad/Resolution.cs` | resolution adequacy (`00_07` HW.51) — does a declared or DERIVED feature (shank↔channel gap, lattice thickness) fit the voxel its own assembly asks for (`2·voxel` represented / `4·voxel` volume-honest); walks the parsed record tree, not the JSON. HARD carrier — `ResolutionTests` + a line in every `verify` reporter |
| `src/SilkenCad/WallScan.cs` | wallParam critical-threshold scan (`scan`) → the CEM working window (printable + open-pore + percolating); pure-managed, no render. The sweep bounds follow the manifest's topology, because the param is a band on sheet and a level on network |
| `src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb SDF on the shank (Zone-1 solid, no channel / Zone-3 channelled) + a DIN-471 groove only where `MechanicalLock.HasGroove` (picogk #0a); render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø29.8 — derived from the board target, root ⚖️ 2026-09-29, applied 2026-09-30): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + the capsule's SINGLE face-seal O-ring groove (depth · width · radii DERIVED from the `o_ring` block + the socket band shared with the radome — `CathodeFlange.ORingGroove*`, `00_07` HW.33 branch (а), applied 2026-09-14; nothing stored); the flange sheet draws the groove as geometry in both readers and its depth tolerance as loud absence |
| `src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø29.8 since the root, 2026-09-30): hollow dome (picogk #9 INVERTED — hollow is intended) + shield bell with the ratified flat crown + a local internal RIM BOSS (`Radome.Boss*`/`SealLand*`: socket band outside ⊥ seal land inside, every term a MINIMUM; rim cavity ≤ Ø20.37 at the 80 % gland fill, the ceiling HW.9 takes as an input) + bayonet socket (cut in the outer band only) + PCB cavity + the VENT FACET (inward pad, Gore target ring, Ø1.0 hole) and the BME280 POCKET (duct · chamber · bridge) — `Radome.Vent*`/`Pocket*`, ⚖️ 2026-09-29; the rim is FLAT — the O-ring groove is the flange's, derived from the `o_ring` block both manifests carry. ⚠️ The raised COLLAR that carries the lugs is modelled on NEITHER part, so the socket keeps its L-slot until the collar leg reshapes it (female ⊥ male halves of one band — the class header); the two requirements any collar model must meet — the rim clamp (`02_02 §3.5`) and the locking torque (`00_07` HW.26) — and why the collar is not modelled live in «Radome / Деталь 4» and «Deferred» below; crown dims — `01_04 §5.5` |
| `src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, 02_02 §4.4): bayonet datum via a `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates (`BuiltFlange` — the ONE home of the inboard clamp, read by render and lug metric alike); pure mate-math (xUnit) + render interference (`verify`); `Parts` — the bodies `build --parts` writes, each in the assembly frame |
| `src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK thermal-break sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (press-fit, smooth bore; flange-shoulder deferred, bench-gated; no hex — the anti-rotation of `01_01 §4.3` C was dropped on its wind ground, ⚖️ 2026-10-03) |
| `src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, 02_02 §4.5): press-fit interference (Zone1↔2 line-to-line · Zone2↔3 = Ø9-in-Ø11 clearance F1) + insertion budget + span; reuses `Assembly.Build` + the Zone-1 envelope; pure mate-math (xUnit) + render (`verify`); `Parts` — the bodies `build --parts` writes (`HasBusWire`/`HasLiner` are the predicates `Build` reads too) |
| `src/SilkenCad.Leap/` | vendored LEAP source compiled in (`ImplicitUsings` ON, warnings relaxed — not ours; picogk #6) |
| `extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |
| `tests/SilkenCad.Tests/` | the HARD regression gate (pure-managed xUnit — CEM parse, SDF math, flood-fill, mate arithmetic, FE closed-form calibration, resolution adequacy). ⛔ Not a scaffold: `cad_smoke.yml` job `logic` runs it on every PR touching this tree |
| `global.json` · `Directory.{Build,Packages}.props` · `.editorconfig` | pinned SDK + CPM + lint |

## Verify locally

```bash
export PATH="$HOME/.dotnet:$PATH"            # .NET 9 SDK (pinned in global.json)
cd tools/cad
dotnet build SilkenCad.sln                                                  # 0W/0E
dotnet run --project src/SilkenCad -- smoke                                 # foundation self-test
dotnet run --project src/SilkenCad -- build  cem/anchor_zone1.pine.json     # → out/*.stl
for f in cem/*.json; do case $f in *golden*|*_provenance*) continue;; esac; \
  dotnet run --project src/SilkenCad -c Release -- build $f; done       # the WHOLE set → out/*.stl (seconds per part)
dotnet run --project src/SilkenCad -- build  cem/anchor_axial_stack.json --parts   # + out/<name>.<part>.stl per body, all in the assembly frame (no collar modelled → radome overlaps flange; zone1 = solid envelope)
dotnet run --project src/SilkenCad -- verify cem/anchor_zone1.pine.json     # → out/*.metrics.json (exit 0/1)
dotnet run --project src/SilkenCad -- scan   cem/anchor_zone1.pine.json     # → out/*.wallscan.json (wallParam working window)
dotnet run --project src/SilkenCad -- draw   cem/ti_coin.json               # → out/*.svg + *.dxf (engineering drawing, pure-managed)
dotnet run --project src/SilkenCad -- fea    cem/anchor_zone1.pine.json --sweep   # → cache/fea/*.json (apparent stiffness; COMMITTED output, pure-managed)
dotnet run --project src/SilkenCad -- render cem/anchor_zone1.pine.json     # → out/*.png (PicoGK viewer; needs a display — macOS desktop, not headless CI)
```

`out/` is gitignored, so an STL there is as old as the last time someone built it, and no gate sees it go stale — a manifest or a generator can move on while the file stays. Rebuild the whole set (above) before looking at the parts or attaching them to a letter; the full anchor along its axis is `anchor_axial_stack.stl`, the capsule end `anchor_assembly.stl`, and `--parts` on either writes each body beside it in the same frame (`out/<name>.<part>.stl`) together with the ⛔ lines of what the CEM does not model.

## Gotchas (hard-won — read before touching the generators)

- **Headless:** run inside `Library.Go(voxel, task, bEndAppWithTask:true)`. The v1.6
  `new Library()` headless pattern is stale in v2.2 (runtime aborts: "relies on
  Library::Go"). `bEndAppWithTask:true` exits with the task → no viewer block. ⛔ Not CI-able on a hosted runner: `Library.Go` SIGSEGVs (139) there — see CI below.
- **Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`**, *not*
  `voxBounding.voxIntersectImplicit(...)`: the latter yields a malformed (background-0)
  OpenVDB level set at fine voxel on thin bored parts → an **uncatchable native abort**
  (`libc++abi … ValueError: expected grid A outside value > 0, got 0`).
- **A FILLED (solid) body must come from ShapeKernel `voxConstruct`, NOT the SDF ctor.**
  The symptom is real (measured: a Ø11 shank read ~17 mm³ instead of ~1700), but the mechanism is a
  field left **OPEN at the bbox caps** — the old «narrow band excludes the core» reading was falsified
  2026-09-12 (a CLOSED SDF solid renders at 99.7–99.8 %; picogk gotcha #9). The gyroid is closed by its
  envelope intersect. `voxConstruct` stays the default because it cannot be got wrong by forgetting to close a field.
  Pattern: solid = `BaseCylinder().voxConstruct()`; thin features (barb ridges) = SDF `BoolAdd`
  (`MechanicalLock.cs`, the Ti-coin split). A `verify` solidity gate guards the regression.
- **`ImplicitRadialGyroid` is degenerate near r=0** (cylindrical singularity) — use a
  cartesian gyroid for small rods (still bicontinuous).
- **Gyroid `wallParam` is DIMENSIONLESS** (the gyroid eq ∈ [-1.5, 1.5]), not mm; a clean
  wall needs `wallParam ≪ amplitude`. **Porosity is voxel-dependent → MEASURE it** (a
  coarse voxel under-resolves voids → falsely LOW porosity: 0.4–0.5 mm read 21–28 % where 0.1 mm reads ~65 %).
- **Voxel-resolution floor:** sub-100 µm pores need voxel ~0.03 mm → huge grids. The Ø11
  anode renders cleanly at 0.1 mm (pores ~2.5 mm); realistic 300→100 µm pores are the
  HW.33 ceiling. ⚠️ **The printability half is TOPOLOGY-dependent and the `≈1.2 mm` this line
  carried is the SHEET number** (measured 2026-09-12, `tools/in_silico/scripts/66_gyroid_ligament_thickness.py`):
  at 65 % a sheet WALL is 0.12·period while a network LIGAMENT is 0.36·period, so at the 200 µm
  SLM floor the minimum printable pore is **≈0.33 mm** on the shipped network branch. What still
  holds: the 100–150 µm PERIPHERY is un-printable on both machines (500 µm clears SLM, 300 µm
  clears µ-LPBF). `stepped` is the one SKU still on the sheet formulation, so 1.2 mm is live for
  it. Ground + declared ceilings: `01_01 §5.5`.
- **A continuous radial gradient keeps POROSITY only up to ~0.8× period ratio — and shears the CELL with height at any ratio:** a spatially-varying
  frequency makes the SDF non-Eikonal (`|∇eq| ∝ f`); the parasitic `∇f·coord` term collapses
  porosity (measured 67→42 % at period 2.5→1.3 mm). Keep continuous gradients gentle — and the
  ~0.8× is a POROSITY bound (from one collapse, read on the whole part): until the HW.33 verdict Z was scaled by the same
  2π/P(r), so the phase gained a z·k′(r) term that grows with height — a volume-keeping SHEAR of the
  cell: the porosity by height stayed flat while, measured 2026-10-22 (`cellshape`), the top of every
  period-graded SKU was compressed to 0.42–0.49 of its nominal along one axis, DA 3.3–4.3, and its specific surface rose to 1.30–1.44 of nominal; ⚖️ ratified and applied the same day (`00_07` HW.33 (в), `01_01 §5.5`):
  one axial period, the rim's — the shipped part reads DA ≤ 1.25 at every height. For a
  STRONG pore contrast use `topology: stepped` (µ-LPBF only, not an SLM candidate — `01_01 §5.5`; constant-period zones → distortion only at the
  thin boundary ring). A phase-correct strong continuous gradient needs period-tensor/conformal
  (Noyron/nTop-level), beyond this demo. **Per-shell porosity uses cumulative-diff** (thin rings
  under-count metal on distorted geometry).
- **`ImplicitUsings` must stay ENABLED** for `src/SilkenCad.Leap` (vendored LEAP source
  relies on implicit `using System` / `System.Collections.Generic`).
- **`out/` + `imgui.ini` are gitignored** (derived / viewer runtime) — but **`cache/fea/` is NOT**: FE results are committed, because canon quotes them and a number canon quotes has to be diffable. Native runtime
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
- **`render` (macos-15)** — `dotnet build` (hard, both OSes) + `verify` metrics (best-effort:
  `Library.Go` SIGSEGVs / exit 139 on the headless hosted runner — no Metal/display context,
  CI-confirmed 2026-06-20 on macos-14, re-confirmed 2026-10-16 on macos-15) + a CycloneDX SBOM + metrics artifacts.

**Local `dotnet run -- verify` stays the PRIMARY metrics gate, and THIS LINE IS ITS HOME.**
A self-hosted macOS-with-display runner would re-arm render-verify as a hard gate; until
then CI mirrors the local run and cannot replace it (the reason is above: `Library.Go`
SIGSEGVs headless). ⛔ Do not cite `00_07` HW.1 for this: that item is about the anchor
CAD→factory route and says nothing about which gate is primary — two files pointed at it
for this sentence, so the claim was circular and lived nowhere.

## Status & deferred

**v2 graded anode shipped** — three CEM-driven grading strategies, all MEASURED (the "which is best"
answer is open, and on the porosity axis it is BIOLOGY's to give — ⚖️ 2026-09-17, `01_01 §5.5`; the
generator is unbiased, not opinionated):
- **continuous cell-size** (`GyroidPeriodRimMm`): the ~0.8× limit is a POROSITY limit; the declared P(r) is the axial and tangential period, while the radial step is 17–20 % shorter in the outer third at every height —
  flat porosity, smooth radial pore taper at the bottom — sheared by height, about half the nominal
  along one axis at the top (`cellshape`, `01_01 §5.5`; ⚖️ `00_07` HW.33).
- **porosity gradient** (`GyroidWallParamRim`): clean monotone profile (the "softer rim").
- **stepped heterostructure** (`Topology: stepped`, `ZonedGyroid`): strong ~2× pore contrast at
  constant porosity — µ-LPBF only: ⚖️ 2026-09-17 it is NOT an SLM candidate (`01_01 §5.5`). Own SDF, not LEAP `ImplicitModular` (`FunctionalScaleTrafo` is a hard-coded
  Z-demo; LatticeLibrary upstream is dormant and our pin is its `HEAD main` — check that with `git ls-remote`, never by age).

5-SKU per-species sweep (pine · oak · broadleaf · mangrove · tropical) + the `graded_porosity` and `stepped` demos — the roster is `ls cem/anchor_zone1.*`.

**ARCH.25 connectivity (shipped)** — `Connectivity.cs` adds a two-phase topological audit
(open-pore↔Archimedes · percolation↔EAAE flow-through · solid-island↔AM/electrical · closed-pore↔trapped-powder · specific-surface
↔EBFC-area) as a fast display-less xUnit gate; `verify` adds open≥95% · solid-disc≤2% · percolate
axial+radial. Two-phase resolution: **pore** OK at the coarse step, **solid** needs ~period/24 (a coarse
grid fragments thin walls into false islands AND merges the sheet gyroid's two pore labyrinths — at
period/16 the island FRACTION already reads ≤0.3 % while the labyrinth COUNT is still wrong on every
period-graded species SKU; skill `picogk` gotcha #8). ⚠ That calibration is SHEET-era: since the
network verdict landed (2026-09-11) no shipped SKU has two labyrinths to merge, so the shipped set no
longer exercises the period/24 rule — its carrier is now a dedicated sheet-held pin (`picogk` #8).

**Mechanical-lock barbs (shipped)** — `MechanicalLock.cs` adds annular asymmetric **ratchet barbs** on
the Ti shank (`01_01 §4.3 A`, HW.26 — the lock against PEEK cold-flow creep) and, on an end that still
carries one, a **DIN-471 groove** (`§4.3 B`): ⚖️ 2026-09-18 the ring as a backup was removed on BOTH ends
and the Zone-3 groove from the geometry; the Zone-1 groove stays until G1/G3 and bounds nothing
(`MechanicalLock.HasGroove`). Own SDF (4th, ratchet `R(z)`), solid `BaseCylinder` + thin barb-ridge
`BoolAdd` + groove-ring `BoolSubtract` where `HasGroove` + a central bore (`0` ⇒ SOLID shank — the Zone-1
end, whose anode carries no core; `Ø1.35` ⇒ cathode channel the welded bus wire threads, `01_01 §1.4`). Metrics MEASURED off the profile (barb count /
height / base, groove depth) + a **self-support face angle** (Noyron manufacturing-awareness): the
ratchet self-supports printed leading-ramp-down as a SEPARATE part (Ti64 LPBF 60° downface, Sa≈15µm);
on the integrated Zone-1 body the anode's `01_02 §1.6` tip-down puts the steep face down at 20° — open,
`00_07` HW.26 G4. Zone-1 Ø11 + Zone-3 placeholder Ø (canon Ø11 lands with the collar, HW.8.9). Grounded over canon §4.3:
tooth over-spec resolved at h=0.28; DIN-471 groove = real shaft dims (was off-spec 0.8×0.6).

**Cathode flange / Деталь 3 (shipped)** — `cathode_flange` CEM → solid Ti flange Ø29.8 (= radome Ø, derived from the board target — root ⚖️ 2026-09-29, applied 2026-09-30; Ø25 frozen before) reusing the
§4.3 lock for the barbed Zone-3 shank (`CathodeFlange.ShankCem` mapping — the same local ratchet profile; the ±1 direction knob was removed 2026-09-13, HW.26; no groove on this end since 2026-09-18) + 3 radial **bayonet lugs**
(`LocalFrame(pos, radialZ)`) + Ø1.35 bus channel (the welded bus wire threads it) + the capsule's one O-ring groove — its FACE seal; the second sealing element, the channel's own closure at its exit, is REQUIRED since 2026-09-18 and not in geometry (`00_07` HW.34) — on the top face (1.344 × 2.315 at r 10.485–12.8 — depth = CS·(1 − 0.245), width = ring section / (0.80 fill · depth), radii off the socket band; nothing stored, `00_07` HW.33 branch (а) applied 2026-09-14; the flange sheet draws it as geometry in both readers and its depth tolerance as loud absence). `verify` gates solidity (NOT hollow-shell,
gotcha #9), the derived Ø, lugs-fused (bbox extent past the rim — 3 lugs @120° are asymmetric → span ≈ flangeD +
protrusion), barb-count. Top face = pogo pads (coating, not geometry); side/perimeter = cathode catalytic
(O₂ ingress, 02_02 §1.2).

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

**Radome / Деталь 4 (shipped)** — `radome` CEM → hollow PEEK dome Ø29.8 (root 2026-09-30; gotcha #9 INVERTED: the hollow IS
intended → the gate checks the wall, not solidity) + a rounded shield bell (≥3/R≥5, anti-overgrowth) +
bayonet socket (L-slot, mate the Деталь-3 lugs — cut in the OUTER band of the rim boss only) + PCB cavity (⛔ its ≥12 floor is OURS on the CEM dim, NOT antenna↔Ti and NOT the canon ≥8 — `02_01 §5.3`) + a LOCAL INTERNAL RIM BOSS (`Radome.Boss*`: socket band `lug + clearance` = 1.8 outside, seal land `gland width + 2·clearance` = 2.915 inside, rim cavity ≤ Ø20.37 at the 80 % gland fill — every term a minimum, so a CEILING handed to HW.9 as an input, ⚖️ 2026-09-14; ≤ Ø15.57 on the Ø25 dome) with a FLAT rim: the single O-ring groove is the flange's, and the land here closes it. `verify`
gates hollow-fraction / bell-rise / cavity / mate-fit / **seal land solid over the full rim face** (a rendered slab measurement, `SealLandSolidFraction` > 95 % — flat rim, no counter-groove, no entry slot in the land). **🏁 Anchor-CAD family complete** (coin→anode-v2→
ARCH.25→barbs→Деталь3→Деталь4). ⚖️ MATE-Ø radial: RATIFIED 2026-09-10, boss APPLIED 2026-09-14 — Ø25 stays (until the root opened it for the board, 2026-09-30 → Ø29.8), lugs go inboard, and the rim boss carries both the bayonet socket and the seal land; the enclosing `skirt` is WITHDRAWN because it cuts the lower cavity past the flange rim and so deletes the face the ratified O-ring seals against. ⚖️ The bayonet-Z half was RATIFIED 2026-09-11 (`02_02 §4.4`): the lugs move to a RAISED COLLAR above the sealing face, at the Z `Assembly.RequiredLugZMm` derives (20.5) — NOT modelled: strength does not size the collar's wall (model 73, `02_02 §4.4`, 2026-10-01 — the process floor does; ⊕ 2026-10-13: at the nominal squeeze — at the window top `88` asks ≥ 0.28 mm, a conditional root-package member, ⚖️ founder 2026-10-13), a placeholder would print on the flange sheet as a decision, and the non-zero running clearance the collar needs (model 82, `02_02 §4.4`: route rows 0.08–0.22 mm, board ceiling Ø19.53–19.81 at wall 0.2; the collar drawing's fit picks the row) moves the root (held for the ONE root move after axis 3 of the RF mock-up, ⚖️ founder 2026-10-13, `00_07` HW.9). The flat crown R5 is APPLIED (2026-09-22, after ⚖️ HW.30 set the pad beside the piezo), so `draw radome` is refused on TWO grounds now: the collar still reshapes the socket, and the BME280 pocket floor is a PLACEHOLDER moved by the B2B / rigid-flex height (`00_07` HW.29). ⊕ 2026-10-06 (the ground dates from 2026-10-05): THREE — the pocket gasket gap `pocket_gasket_gap_mm` is a PLACEHOLDER 0 until the moulder's profile gives the compressed bead (`00_07` HW.32); the live list is the `draw radome` leg of `00_07` HW.1, mirrored by the deferral note in `radome.json`. ⊕ 2026-09-30 (root + `00_07` HW.32): the VENT FACET — an inward pad on the vertical inner wall (8.5 wide at 60°, between two entry slots) carrying Gore's target ring and one Ø1.0 through-hole — and the BME280 POCKET (a duct on the boss top outside the rim cavity, a chamber over the RF-deck edge inside it, a bridge above the board edge; ≈ 89 mm³ of air, τ ≈ 12 s) are APPLIED (`Radome.Vent*` / `Pocket*`); `verify` gates ring-fit, hole ≤ active area, pocket ≤ 300 mm³ and the housing staying off the board envelope. The facet's seat band (8.56 mm) answered the verdict's own conditional: VE70205 fits, VE70308 does not.

**Capsule-end assembly / mate-audit (shipped)** — `Assembly.cs` + `anchor_assembly` CEM brings Деталь 3 ↔ Деталь 4
into one frame at the bayonet datum (radome lock-groove ↔ flange lugs) and MEASURES the residual mismatch (radial
−2.0 · bayonet-Z 5.0 — it read 6.42 while the chain carried an O-ring face gap of 1.424; that term is ZERO under
branch (а), applied 2026-09-14, so the field is gone and the number fell because a term left, not because one moved ·
RF 8.0 mm) + models the two MATE-Ø candidates (`mate_strategy` skirt vs inboard = the flange Ø). ⚠️ The `RfClearanceMinMm = 12` it is judged against is the CEM's number, NOT canon: `02_01 §5.3` asks for `≥ 8` and calls 12 the outcome of a proposed board stack (00_07 HW.33, 2026-09-11).
An AUDIT table, NOT a part pass/fail — the mismatch is the real un-reconciled Z-stack (→ HW.17/HW.8), so `verify`
exits on a broken render only; the numbers are asserted by the pure xUnit suite (`AssemblyTests`). Reuses
`CathodeFlange.Build` · `Radome.Build` · `MeshUtility.voxApplyTransformation` (lift) · `BoolIntersect`. Z-stack
inputs mirror `tools/in_silico/scripts/52`. Canon `02_02 §4.4`.

**Zone-2 sleeve / Деталь 2 (shipped)** — `zone2_sleeve` CEM → plain hollow PEEK tube via `BasePipe` (bore Ø11 / OD
Ø15 wound / 50 mm, frozen `01_01 §1`). The simplest part: no barbs/grooves/hex — the smooth bore receives the Ti
shanks at 150 °C (no hex anti-rotation on this part — `§4.3 C` was dropped on its wind ground, verdict 2026-10-03, `00_07` HW.26). `verify` gates hollow + OD = bore+2·wall + length.

**Full axial stack / mate-audit (shipped)** — `AxialStack.cs` + `anchor_axial_stack` CEM brings ALL FOUR zones (anode
→ Zone-2 sleeve → flange → radome) into one axis and MEASURES the press-fit interfaces the capsule-end never touched:
**Zone1↔Zone2 = 0.00 mm line-to-line** (real +interference = the press-fit band on bench — no ISO 286 table class is ratified: the band is solved from the Lamé window, `00_07` HW.3, only its inputs open) · **Zone2↔Zone3 = −1.0 mm
= the Ø9-in-Ø11 clearance (F1, shank Ø placeholder → HW.8.9)** · insertion budget 18 mm · overall stack length 93 mm (anode bottom → flange top; embedded depth 90 — to the flange UNDERSIDE = the bark line, ⚖️ HW.33 2026-09-18; 63 / 60 until ⚖️ HW.26 G1 2026-10-12) · bus continuous.
The Zone-1 insertion IS its own lock's whole shank (⚖️ founder 2026-10-12, `00_07` HW.26 G1, branch (А); verdict home
`01_01 §4.3` A): the stack names that lock by file (`zone1_lock_manifest`, never a copy of its numbers), `AxialStack.Load`
resolves `Zone1ShankLengthMm` from it — the manifest has no insertion field any more, so there is nothing to drift — and
`MechanicalLock.InsertionWindowMm` derives the window from the shank's free end, PEEK-contact zone end → end of the shank
(⚖️ 2026-09-18: no ring is fitted as a backup). The shipped insertion is the window's DEEP end; the PRESS FIXTURE holds it there,
not the part (⚖️ `00_07` HW.26 2026-10-12 — the gyroid-to-shank step is zero on a Ø11 anode); `verify` prints the insertion as the whole shank. Until G1 a typed 30 mm placeholder sat outside
the window and `verify` flagged it.
An AUDIT table like the capsule-end — render-sanity exit only, findings asserted by `AxialStackTests`. Render uses the
Zone-1 envelope (solid Ø11; a press-fit cares about OD, not porosity). The render overlap sleeve∩capsule (~8 mm³) is the
flange SHOULDER resting on the sleeve top face, NOT the shank (Ø9 floats in bore Ø11). Reuses `Zone1Anode.Envelope` ·
`Zone2Sleeve.Build` · `Assembly.Build` · `voxApplyTransformation` (Noyron Boolean multi-part). Canon `02_02 §4.5`.

**Welded bus wire (shipped, `01_01 §1.4` / HW.1 / HW.34)** — `bus_rod_diameter_mm` > 0 declares the WIRE, an
assembly part: since 2026-09-18 the anode is generated WITHOUT a core (`Zone1Anode.InnerRadiusMm` = 0, lattice
to the axis) and the wire body lives only in `AxialStack`, starting at the anode's top face — where it is
welded. ⛔ `BuildMonolithic`/`BusRod` were REMOVED with the printed-core branch; `fea --with-rod` went with
them, because it measured a body the factory never receives. ⚠️ **The ratified fabrication is a WELD** (`00_07` HW.34, 2026-09-10: an as-printed rod carries `ENDURANCE_OVER_YIELD × AS_PRINTED_DERATE`, a welded cold-drawn wire does not), so the rod arrives as bought wire plus a weld and its tolerance/`Sa` come from a wire spec canon does not carry. Porosity is a property of
the printed part, and since the core left it the reference envelope is the FULL cross-section — the golden
baselines were re-measured 2026-09-18 and the sub-floor shares moved (`01_02 §6`). ⛔ The `verify` line that
MEASURED the fused rod is gone with the rod. The wire runs anode-top→cathode-channel→flange pad; `AxialStack.BusRodClears` audits rod + 2·liner **<** channel — STRICT since 2026-09-11 (`00_07` HW.34): at `≤` the frozen trio `1.0 + 2×0.15 = 1.30` passed against a Ø1.30 bore, i.e. the gate blessed a ZERO nominal clearance — a true statement about the sum and a false one about the assembly. ⛔ Its declared ceiling did not change: it judges NOMINALS and a DIAMETER, so green here is not proof that a real pair mates, and it says nothing whatever about the liner's LENGTH or its ends. ⚠️ **That gap is no longer an open judgment: the axial extent was RATIFIED 2026-09-12** — the tube spans the whole Zone-3 channel, flush at the pogo face, the lower end protruding ≥ 1.0 mm into the PEEK gap, captured at ONE end only (`01_01 §1.4`, `00_07` HW.34). ✅ Both landed 2026-09-12: the tube has a body in `AxialStack` and a Z check of its own — **F4 `LinerCoversChannel`**, which exists because F3 compares a DIAMETER and therefore cannot see a tube shorter than the channel. ⚖️ The two questions that stayed open here were RATIFIED 2026-09-18 (`00_07` HW.34): the tube is captured at the UPPER end (the pad plane), and the channel gets its own closure at its EXIT — the Ti↔PEEK path is not sealed by design, so that closure guards the capsule. Both are requirements in canon; their geometry waits on the pogo pin P/N (HW.9).

**Engineering drawings + render (shipped)** — `draw <cem>` → SVG (human) + **DXF via netDxf** (factory-native, opens
in AutoCAD/Fusion), pure-managed, consuming the CEM `ToleranceSpec`/`NotesSpec` (fits; GD&T datums;
coating-restriction; lattice-spec). §7/§8 DECIDED: DXF+SVG / ISO 1st-angle / CEM-tolerances.
⚠️ **«Fits as Lamé-µm, NOT a blind ISO-286 `H7/s6` on a PEEK bore» is the canon REQUIREMENT (`01_01 §4.2`), and this
line used to state it as if it were the shipped reality.** It is not: `cem/zone2_sleeve.json`'s 5–34 µm is the ISO 286
table (`tools/in_silico/lib/constants.py`), which Lamé consumes to compute a contact pressure rather than produces.
The generator briefly hid that by appending a hard-coded «(Lamé, E_PEEK-aware)» to the line — invented PROVENANCE on a
true value, removed — and the engineering verdict is RATIFIED (2026-09-18, `00_07` HW.3): no table class; the band is solved
from the Lamé window, and only its inputs are open. **This tract prints QUANTITIES; where a
number came from is engineering text and belongs in the CEM.**
⛔ **The shipped-kind roster is `Program.Draw`'s `switch`, not this paragraph** — it carried one and went stale the day
a kind landed. Phasing, and the kinds deliberately NOT drawn with their grounds, live in `docs/drawings_program.md §7` —
named there and not here, for the same reason.
The NORM — why the drawing comes from the CEM and not the mesh, the two readers, the loud-absence rule, what the
acceptance contract must carry — is canon `01_02 §6`; `docs/drawings_program.md` stays the research + phase roster.
`render` / `section <cem>` → PicoGK native-viewer PNG (presentation gallery `docs/images/cad/`, rebuilt by
`scripts/render_gallery.sh`, NOT SSOT). ⚠️ **Not SSOT ≠ free to lag:** those SVGs are committed and open straight
from GitHub (blob-rendered), so they are the drawings an outsider actually reads — and nothing re-runs the script
for you. (⛔ `wiki:sync` does NOT carry them: it syncs canon `NN_NN_*.md` and copies an image only where a doc
EMBEDS it as `![…](…)`, and none does.) Touch `Drawing.cs` or a CEM ⇒ re-run it and commit the SVGs; `DrawingTests` reds if their CONTENT drifts
from the shipped manifests, and — since every sheet prints the SHA-256 of its manifest (title block + footer + DXF) —
if a published sheet no longer names the manifest shipped today, so any byte change to it, a note included, means a
redraw (ceiling: not the sheet's own layout bytes, not its `rev`; the PNGs are pinned by nothing). The same identity
check also runs locally, without dotnet, before every push that touches a CEM, a sheet or `Drawing.cs`
(`scripts/cad_gallery_freshness.rb` in `.githooks/pre-push`) — it reads the COMMIT, so a redrawn sheet you forgot to
`git add` is refused too; it detects a stale sheet, it never redraws one.
LEAP 71 ships metal engines WITHOUT 2D drawings — code is the engineering intent.

**Deferred:** the raised-collar implementation (the rim BOSS is applied since 2026-09-14; the bayonet-Z reconcile itself is RATIFIED 2026-09-11, `02_02 §4.4`: the mismatch is t/2 + lockGrooveZ — two positive terms now that the O-ring face gap is zero under branch (а) — so the lug takes a Z of its own on a collar, `Assembly.RequiredLugZMm` = 20.5; ⚖️ 2026-09-14: designed under the Ø15.57 ceiling (Ø20.37 since the root, 2026-09-30) and handed to HW.9 as an INPUT, not gated on it — what holds the collar is no longer its WALL: there is still no bayonet load model, but since 2026-10-01 model 73 (`02_02 §4.4`) shows the force does not size the wall, the process floor does; what holds it is its running clearance in the radome channel: the collar needs a non-zero one (model 82, `02_02 §4.4`, computed 2026-10-05), and any non-zero clearance moves the root (held for the ONE root move after axis 3 of the RF mock-up, ⚖️ founder 2026-10-13, `00_07` HW.9), and a placeholder would print on the flange sheet as a decision; bench follows at HW.8.8) · ~~the flat crown R5~~ **APPLIED 2026-09-22** (⚖️ 2026-09-11; its gate ⚖️ HW.30 settled the pad BESIDE the piezo): `bell_radius_mm` now DRIVES the edge round, `bell_rise_mm` stays the canon floor-check, and `hollow_fraction`'s reference solid was recomputed in the SAME commit — measured bbox 25.0 × 25.0 × 18.0, rise 5.0, internal height 16.0 · the shank-Ø
press-fit reconcile (the Ø9 shank placeholder vs bore Ø11, HW.8.9; no table class is ratified — the band comes from the Lamé window, HW.3) · a phase-correct strong continuous gradient (period-tensor/
conformal). ⛔ The print-thickening parameter for the FE was listed here and **shipped 2026-09-14** as `fea --dilate` — removed; what it still cannot say (the printed excess per face orientation) is a vendor answer, `00_07` HW.51. ⛔ The C-vs-n porosity sweep was listed here and **shipped 2026-09-12** as `fea --fit` — removed. ⛔ Euler-χ / tortuosity cross-checks were listed here as deferred and **shipped 2026-09-09** as `TopologyCrossChecks.cs` — removed.

## License

Our code: AGPL-3.0 (repo `LICENSE`). Vendored: PicoGK (NuGet) + ShapeKernel +
LatticeLibrary — **Apache-2.0** (LEAP 71); see `/NOTICE`.
