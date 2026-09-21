---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin coupon, the Zone-1 gyroid anode, the mechanical lock, the cathode flange, the PEEK radome) and the CEM (Computational Engineering Model) manifests that drive them; the voxel-FE elasticity tract (`fea`, `fea --fit` → Gibson-Ashby C/n pinned to canon by scripts/fea_canon_sync.rb); the resolution-adequacy and local-verify gates (`dotnet run -- verify`); the CEM provenance gate (every numeric field carries a declared ground); and the engineering-drawing tract (`draw <cem>` → SVG for people + DXF for the factory, an absent field prints NOT SPECIFIED IN CEM, the committed gallery under docs/images/cad lags its generator unless re-run). The non-obvious gotchas live in gotchas.md, one generated index line each in the body — open it before touching a generator, a manifest, draw, fea or verify; the task recipes live in tasks.md — open it before starting any CAD task. Routes to 01_02 §6 (stack, Noyron methodology, drawing norm) + 01_01 §5 (anchor geometry) + tools/cad/README; does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"build the Ti-coin STL\", \"make a factory drawing / DXF\", \"add a surface-finish or coating note to a CEM\", \"what is the anchor lattice stiffness / run the FEA\", \"is this feature resolvable at this voxel\", \"set up the .NET CAD project\"."
---

# PicoGK Code-as-CAD (`tools/cad`)

Navigation aid + non-obvious gotchas. The **SSOT is the docs + code + `tools/cad/README.md`
below** — this skill points, it does not restate (so it can't drift). Verify a fact at its
home before trusting a summary. Methodology (per LEAP 71 Noyron): a CEM is a *deterministic
algorithm*, not generative ML — an agent writes the generator, the generator computes the geometry.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|----------------|
| `tools/cad/README.md` | Operational home: layout, local-verify recipe, a short gotcha subset (the full list is this skill's `gotchas.md`), license |
| `docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md §6` | PicoGK stack (.NET 9, PicoGK 2.2 NuGet + ShapeKernel/LatticeLibrary submodules), Noyron methodology, real API, honest caveats — **and the ⛔ register of what the method deliberately does NOT take** (V&V 40 · MBD/AP242 · PLM · digital signing · FsCheck/Stryker · ISO/ASTM 52910/52911 · multi-resolution), each with its ground: read it before proposing any of them again — **and the engineering-drawing NORM**: why a drawing is derived from the CEM and not the mesh, the two readers (SVG clips, DXF does not), the loud-absence rule, what the acceptance contract must carry. The tools-local file below stays the RESEARCH + phase roster |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §5/§6` | Anchor geometry: porosity nominal + acceptance band · pore gradient · Gibson-Ashby C/n and the MEASURED apparent stiffness per axis · Ti-coin Stage-2 coupon. ⛔ Values live THERE — this row names topics, never numbers |
| `docs/00_07_Action_Plan_Tracker.md` HW.1 / **HW.33** · HW.26 · HW.34 · HW.3 · HW.8 · HW.51 | Build state + the anchor geometry audit's OPEN legs (its ratified verdicts live in canon — `01_01 §5` · `02_02 §3–§4` · `01_04 §3.1/§5.5` · `02_01 §5.3`; the item's `**Стан:**` names each home). The CAD-facing open legs live in their own items: HW.26 the Zone-1 lock integration (G1 · G3 · G4) and the fate of the one groove left (its ring verdict is homed in `01_01 §4.3 B`) · HW.34 the pad-plane geometry and channel closure (after the HW.9 pin) and the coaxiality NUMBER (after HW.26 G1) — its ratified liner nominal and coaxiality FORM are homed in `01_01 §1.4` · HW.3 the Zone1↔2 fit band · HW.8 the placeholders (Zone-3 shank Ø, Zone-1 insertion) · HW.51 convergence (the radome numbers are ratified design points — `02_02 §3.5` · `02_02 §4.4`) |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §6` | Cross-biome 5-SKU (pine/oak/broadleaf/mangrove/tropical) |
| `docs/00_03_TRL_Matrix_HIL_and_Beyond.md §3.6` | Code-as-CAD vs generative-AI; In-Silico for the Hardware stream |
| `tools/cad/docs/drawings_program.md` | Engineering-drawing program: CEM-native DXF (netDxf) + SVG, the ASME-Y14.5≠projection fix, lattice-as-inspection-card, phased §7 rollout |
| `extern/.../README_ImplicitLibrary.md` | LEAP's own implicit/TPMS guide — reference only; the graded v2 did NOT use it (own SDF — `tasks.md` «Graded gyroid») |

## Source Files

| File | Role |
|------|------|
| `tools/cad/cem/*.json` | CEM manifests — the Git-SSOT parameter inputs (`kind` discriminator: `ti_coin`, `anchor_zone1`, `mechanical_lock`, `cathode_flange`, `radome`, `zone2_sleeve`, `anchor_assembly`, `anchor_axial_stack`) |
| `tools/cad/src/SilkenCad/Program.cs` | CLI dispatch — ⛔ the verb roster is the `switch` in `Main`, never a list here. Outside it: `RunHeadless` (the `Library.Go` wrapper); `draw` is pure-managed (no Library.Go), `render`/`section` drive the native viewer |
| `tools/cad/src/SilkenCad/Cem.cs` | CEM records + JSON parse (snake_case). Engineering-drawing PMI lives here: optional `ToleranceSpec` (fits / interference µm / GD&T datums / a LIST of `Features` — a named feature with NO limits still renders, as loud absence) + `NotesSpec` (material/process/**post-process**/surface/coating-restriction/lattice-spec/inspection) on each part record — Noyron-native SSOT, fed to `draw` |
| `tools/cad/src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw <cem>`): **SVG (human) + DXF via netDxf (CAD-native factory deliverable, opens in AutoCAD/Fusion)** — no PDF (never built; `drawings_program §3`). Pure-managed string/entity build, no Library.Go. Consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). Each kind is a `Drawing.X` + `Drawing.XDxf` pair; the roster and the add-a-kind checklist → `tasks.md` «Generate an engineering drawing». ⚠️ gotcha #11 |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) + reuses LEAP `Measure.fGetSurfaceArea` |
| `tools/cad/src/SilkenCad/Golden.cs` | Committed regression baseline of the GEOMETRIC metrics (`cem/<x>.golden.json`, `00_07` HW.33/HW.49) — written ONLY by `verify --write-golden` (the writer prints what moved), keyed by voxel (a run at another voxel is not compared). Pins REGRESSION, never correctness; ⚠️ a manifest with no golden passes `verify` silently |
| `tools/cad/src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-conn flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit. ⊕ Also the MESH SOURCE for `VoxelFea`: `SampleRegion` (with a phase-override hook both FE callers leave null) and `LargestComponentMask` (membership, which `Components` does not keep) |
| `tools/cad/src/SilkenCad/TopologyCrossChecks.cs` | ARCH.25 third phase — Euler-χ / tortuosity / as-printed cross-checks, informational `verify` lines (gotcha #12); also the home of the lattice-thickness constants (`SheetThicknessPerPeriod` / `NetworkThicknessPerPeriod`, `LatticeThicknessMm`) that `Resolution` reads (gotcha #5) |
| `tools/cad/src/SilkenCad/WallScan.cs` | Verb `scan` — sweeps `wallParam` over the CEM's own SDF (pure-managed) and reports the working window (printable ∧ open-pore ∧ percolating); the sweep bounds follow the manifest's topology, because the param is a band on sheet and a level on network |
| `tools/cad/src/SilkenCad/VoxelFea.cs` | **Voxel-FE пружності** (00_07 HW.51/HW.33) — solid-воксель `Connectivity.Grid` → трилінійний гексаедр; матрично-вільний поелементний множник, 8-кольоровий за парністю вокселя, Якобі-CG. Верб `fea`. ⛔ Меш бере лише найбільше гране-звʼязне тіло (плавучий острівець = жорсткий рух), відкинуте — рапортується. Стеля оголошена в шапці класу; числа — `01_01 §5.2`, кеш `tools/cad/cache/fea/` |
| `tools/cad/src/SilkenCad/Resolution.cs` | **Достатність роздільності** (00_07 HW.51) — чи влазить фіча у воксель, якого просить її збірка. Ходить по РОЗПАРСЕНОМУ дереву записів, не по ключах json, і несе ВИВЕДЕНІ величини (щілина стрижень↔канал, товщина ґратки). HARD-носій — `ResolutionTests` + рядок у кожному `verify`-репортері |
| `tools/cad/src/SilkenCad/Probe.cs` | Verb `probe <voxel>` — falsifiable probes of what we believe about the PicoGK KERNEL, not our geometry (gotchas #1 · #9); probe B can kill the process by design, so A runs first |
| `tools/cad/src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb SDF on the shank (Zone-1 solid shank, no channel / Zone-3 channelled); the DIN-471 groove is OPTIONAL per end (`MechanicalLock.HasGroove`, gotcha #0a); render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `tools/cad/src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + the capsule's SINGLE face-seal O-ring groove on the top face — depth · width · radii DERIVED from the `o_ring` block and the socket band shared with the radome (`CathodeFlange.ORingGroove*`; 00_07 HW.33 branch (а), applied 2026-09-14), nothing stored; the flange sheet draws it as geometry in both readers and its depth tolerance as loud absence |
| `tools/cad/src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + a LOCAL INTERNAL RIM BOSS (`Radome.Boss*`/`SealLand*`: socket band `lug + clearance` outside ⊥ seal land `gland width + 2·clearance` inside; the rim-cavity ceiling (value: `02_02 §3.5`) — every term a MINIMUM, a ceiling HW.9 takes as an input, ⚖️ 2026-09-14) + the bayonet socket, cut in the boss's OUTER band only + PCB cavity; the rim is FLAT — the single O-ring groove is the flange's, derived from the `o_ring` block both manifests carry (gotcha #9 INVERTED — hollow is intended). ⛔ **ONE ratified-but-still-shipped divergence lives in this file:** the CAP is still a FULL HEMISPHERE where ⚖️ 2026-09-11 ratified a FLAT CROWN with an edge fillet (dims: `01_04 §5.5`), and it waits on ⚖️ HW.30 (piezo placement), not on a budget. ⚠️ Applying it silently inflates `hollow_fraction`, because `Validation`'s reference solid still adds a hemisphere — recompute that formula in the same commit — and `bell_rise_mm`/`bell_radius_mm` must become DRIVERS, which today they are not. ⚠️ The raised COLLAR that carries the lugs at `Assembly.RequiredLugZMm` is modelled on NEITHER part — its wall is set by nothing (no bayonet load model), and a placeholder would print on the flange sheet as a decision — so the socket keeps its L-slot shape (clipped to the outer band, pocket `socket band − skin` = 1.6 deep, skin 0.2) until that leg reshapes it: socket and collar are the female and male halves of one band. `verify radome` MEASURES the seal land solid over the full rim face (`SealLandSolidFraction`), the xUnit pins only derive it |
| `tools/cad/src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, `02_02 §4.4`) — bayonet datum via `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates; pure mate-math (xUnit) + render interference (`verify`) |
| `tools/cad/src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (smooth bore; hex + flange-shoulder deferred, bench-gated) |
| `tools/cad/src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, `02_02 §4.5`) — press-fit interference + insertion budget + span; reuses `Assembly.Build` + Zone-1 envelope; pure mate-math (xUnit) + render (`verify`) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts, porosity AND the FE stiffness ratio all drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify` (geometry) or `fea --sweep` / `fea --fit` (stiffness AND the Gibson-Ashby coefficients — a single row is an UPPER bound by construction, and the FITTED `C` itself still moves with the step (the `01_01 §5.2` table), so nothing is quoted without its convergence ladder).

**State** lives in `00_07` (the items in the table above), not here; memory keeps the router `[[project_01_picogk_code_as_cad]]` (⊕ its journal twin `[[log_picogk_cad]]` — the BODIES, with their numbers), and the curator lessons born in CAD sit in their class homes (applying a ratified verdict → `[[feedback_verdict_lifecycle]]`) · `[[project_01_anchor_bus]]` (bus router + the PEEK-liner trap, gotcha #0) · `[[project_01_coin_bakeoff_trl4]]` (the Ti-coin keystone this CAD feeds).

## Gotchas Not Obvious From Docs

**Bodies live in `gotchas.md` — open it before touching a generator, a CEM manifest, `draw`, `fea`
or `verify`.** Below is one generated line per gotcha: the line is the CARRIER, meant to stop you
mid-action; the mechanism and the bounds are in the companion. Numbering is
append-only (`0a` · `0b` · `4a` · `9b` are items of their own).

<!-- PICOGK-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

0. `tools/cad/cem/*.json` is the parameter SSOT, and its `liner 0.15 mm` is now a RATIFIED branch — but read why before you touch it
0a. «CEM json = parameter SSOT» is true only where the manifest SPEAKS — and `cem_canon_sync` guards exactly that half, so the silent half has no gate at all
0b. A manifest can be silent for a SECOND reason, and this one is worse than a default: the record has no SLOT, so the key you write EVAPORATES
1. Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`
2. `ImplicitRadialGyroid` is degenerate near r=0 — use a cartesian gyroid for a small part near its own axis
3. Run headless through `Library.Go(voxel, task, bEndAppWithTask:true)`, never `new Library()` — and headless CI cannot run it at all
4. Gyroid `wallParam` is a DIMENSIONLESS level of the gyroid equation, and the sheet and network branches read it differently
4a. «Porosity is voxel-dependent → MEASURE it», and the suspected cause of the coarse-voxel collapse is REFUTED — both now live in #4 (evidence: `00_07` HW.49)
5. Voxel-resolution floor + gradient distortion — the grid's floor and the printer's floor are different ceilings, and the printable one depends on topology
6. Keep `ImplicitUsings` ENABLED for the vendored `src/SilkenCad.Leap`, and the strict knobs ON only for our own code
7. Set `DOTNET_ROOT=$HOME/.dotnet` when running the apphost binary directly, and look for its lowercase name `silkencad`
8. Connectivity needs WALL-resolution, not pore-resolution — sample the SDF finer than half the thinnest wall, and judge by the COUNT
9. A FILLED (solid) body must come from ShapeKernel `voxConstruct`, NOT `new Voxels(IImplicit, BBox3)` — unless your field is CLOSED, and that exception is measured, not theoretical
9b. A body can render PERFECTLY in its own grid and add NOTHING to the assembly — and its own volume is the metric that hides it
10. `render`/`section` (presentation) need a display + the screenshot is TGA
11. A drawing must never invent or silently drop a field — an absent value prints `NOT SPECIFIED IN CEM`, and the next `??`-default will read as innocent as the four fixed on 2026-08-28
12. `TopologyCrossChecks.cs` (ARCH.25 third phase, 2026-09-09) — Euler-χ / tortuosity / as-printed cross-checks, wired into `verify` as `[nice-to-have]` INFORMATIONAL lines, not the `VERIFY OK/FAILED` gate
13. Every numeric field of every `cem/*.json` must carry a DECLARED GROUND, and this is a HARD gate since 2026-09-12 — adding a field without one reds `docs.yml`
14. A bare `fea --fit` OVERWRITES a canon-pinned cache with a DIFFERENT SPECIMEN, because the filename carries the RESOLUTION and not the SIZE
15. A direction or a sign in a CEM field is read in TWO frames — the author's assembled/world view and the code's part-local frame — so pin the FUNCTION in the part's frame, never the sign
16. A constant-period lattice sampled at a step that divides its period is PHASE-LOCKED — and `--step-div N` takes the step FROM the period, so on a constant-period part EVERY divisor is such a step, by definition
17. `out/` is OUTSIDE every gate we own, and that is where the VENDOR's copy lives
18. A mutation probe that restores a `.cs` with an OLDER mtime is not restored for MSBuild — and the next probe's red is the previous probe's leftover
19. Editing a `cem/*.json` through a JSON PARSER rewrites the whole file, and the reformat hides the one line you meant to change
20. The gallery has TWO artefact kinds with DIFFERENT triggers, and only one of them is pinned — so the reflex that says «re-run the drawing loops» (#18 ⊕) leaves the renders stale by its own wording

<!-- /PICOGK-GOTCHAS-INDEX -->

## Common Tasks

**Recipes live in [`tasks.md`](tasks.md) — open it before you START any CAD task** (a part or SKU, the anchor geometry, the bus wire, a lattice, a drawing, a render, an FE or resolution run, `verify` or `converge`, an assembly audit, a submodule bump). They carry live verdicts and traps inline, so never work a task from memory of this skill.
