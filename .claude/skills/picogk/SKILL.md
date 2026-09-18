---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin coupon, the Zone-1 gyroid anode, the mechanical lock, the cathode flange, the PEEK radome) and the CEM (Computational Engineering Model) manifests that drive them; the voxel-FE elasticity tract (`fea`, `fea --fit` → Gibson-Ashby C/n pinned to canon by scripts/fea_canon_sync.rb); the resolution-adequacy and local-verify gates (`dotnet run -- verify`); the CEM provenance gate (every numeric field carries a declared ground); and the engineering-drawing tract (`draw <cem>` → SVG for people + DXF for the factory, an absent field prints NOT SPECIFIED IN CEM, the committed gallery under docs/images/cad lags its generator unless re-run). The non-obvious gotchas live in gotchas.md, one generated index line each in the body — open it before touching a generator, a manifest, draw, fea or verify. Routes to 01_02 §6 (stack, Noyron methodology, drawing norm) + 01_01 §5 (anchor geometry) + tools/cad/README; does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"build the Ti-coin STL\", \"make a factory drawing / DXF\", \"add a surface-finish or coating note to a CEM\", \"what is the anchor lattice stiffness / run the FEA\", \"is this feature resolvable at this voxel\", \"set up the .NET CAD project\"."
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
| `docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md §6` | PicoGK stack (.NET 9, PicoGK 2.2 NuGet + ShapeKernel/LatticeLibrary submodules), Noyron methodology, real API, honest caveats — **and the engineering-drawing NORM**: why a drawing is derived from the CEM and not the mesh, the two readers (SVG clips, DXF does not), the loud-absence rule, what the acceptance contract must carry. The tools-local file below stays the RESEARCH + phase roster |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §5/§6` | Anchor geometry: porosity nominal + acceptance band · pore gradient · Gibson-Ashby C/n and the MEASURED apparent stiffness per axis · Ti-coin Stage-2 coupon. ⛔ Values live THERE — this row names topics on purpose (it drifted twice by restating them) |
| `docs/00_07_Action_Plan_Tracker.md` HW.1 / **HW.33** · HW.26 · HW.34 · HW.3 · HW.48 · HW.51 | Build state + the anchor geometry audit (founder decisions: orientation-agnostic gyroid (б), Ø11; the June gaps are spent — PEEK/hole chain frozen, FEA-E measured — so the open set is its `**Стан:**`, split still-judged ⊥ ratified-but-unapplied). The CAD-facing verdicts live in their own items: HW.26 ring & groove · HW.34 liner nominal, channel coaxiality, pad plane, channel closure · HW.3 the Zone1↔2 fit band · HW.48 radome provenance · HW.51 convergence |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §6` | Cross-biome 5-SKU (pine/oak/broadleaf/mangrove/tropical) |
| `docs/00_03_TRL_Matrix_HIL_and_Beyond.md §3.6` | Code-as-CAD vs generative-AI; In-Silico for the Hardware stream |
| `tools/cad/docs/drawings_program.md` | Engineering-drawing program: CEM-native DXF (netDxf) + SVG, the ASME-Y14.5≠projection fix, lattice-as-inspection-card, phased §7 rollout |
| `extern/.../README_ImplicitLibrary.md` | LEAP's own implicit/TPMS guide (splitting logic, modular workflow for the graded v2) |

## Source Files

| File | Role |
|------|------|
| `tools/cad/cem/*.json` | CEM manifests — the Git-SSOT parameter inputs (`kind` discriminator: `ti_coin`, `anchor_zone1`, `mechanical_lock`, `cathode_flange`, `radome`, `zone2_sleeve`, `anchor_assembly`, `anchor_axial_stack`) |
| `tools/cad/src/SilkenCad/Program.cs` | CLI dispatch — ⛔ ростер бери з `switch` у `Main`, не звідси: датований перелік верб, що стояв тут, відставав ДВІЧІ (спершу на три верби, потім на `converge`, HW.51), тож його знято. Поза ростером — `RunHeadless` (the `Library.Go` wrapper); `draw` is pure-managed (no Library.Go), `render`/`section` drive the native viewer |
| `tools/cad/src/SilkenCad/Cem.cs` | CEM records + JSON parse (snake_case). Engineering-drawing PMI lives here: optional `ToleranceSpec` (fits / Lamé-µm / GD&T datums / a LIST of `Features`, since 2026-09-11 — the single slot it replaced silently capped a part at ONE toleranced size, which is why the cathode flange could not give its own primary datum a dimensional row; a named feature with NO limits still renders, as loud absence) + `NotesSpec` (material/process/**post-process**/surface/coating-restriction/lattice-spec/inspection) on each part record — Noyron-native SSOT, fed to `draw` |
| `tools/cad/src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw <cem>`): **SVG (human) + DXF via netDxf (CAD-native factory deliverable, opens in AutoCAD/Fusion)** — no PDF (never built; `drawings_program §3`). Pure-managed string/entity build, no Library.Go. Consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). ⛔ **The roster of shipped kinds is `Program.Draw`'s `switch`, never a prose list here** — this line carried one and it was stale within the day. What does NOT rot: each kind is a `Drawing.X` + `Drawing.XDxf` pair, and adding one means adding its shipped-CEM round-trip row (gotcha #11) and its gallery pin. Phasing + the kinds deliberately NOT drawn, with their grounds → `tools/cad/docs/drawings_program.md §7`. ⚠️ gotcha #11 |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) + reuses LEAP `Measure.fGetSurfaceArea` |
| `tools/cad/src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-conn flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit. ⊕ Since 2026-09-12 it is also the MESH SOURCE for `VoxelFea`: `SampleRegion` (sampling with a phase-override hook, unused since `--with-rod` left 2026-09-18 — both FE callers pass a null override) and `LargestComponentMask` (membership, which `Components` does not keep) |
| `tools/cad/src/SilkenCad/VoxelFea.cs` | **Voxel-FE пружності** (00_07 HW.51/HW.33) — solid-воксель `Connectivity.Grid` → трилінійний гексаедр; матрично-вільний поелементний множник, 8-кольоровий за парністю вокселя, Якобі-CG. Верб `fea`. ⛔ Меш бере лише найбільше гране-звʼязне тіло (плавучий острівець = жорсткий рух), відкинуте — рапортується. Стеля оголошена в шапці класу; числа — `01_01 §5.2`, кеш `tools/cad/cache/fea/` (ВЕРСІОНОВАНИЙ, на відміну від `out/`) |
| `tools/cad/src/SilkenCad/Resolution.cs` | **Достатність роздільності** (00_07 HW.51) — чи влазить фіча у воксель, якого просить її збірка. Ходить по РОЗПАРСЕНОМУ дереву записів, не по ключах json, і несе ВИВЕДЕНІ величини (щілина стрижень↔канал, товщина ґратки). HARD-носій — `ResolutionTests` + рядок у кожному `verify`-репортері |
| `tools/cad/src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb SDF on the shank (Zone-1 solid shank, no channel / Zone-3 channelled); the DIN-471 groove is OPTIONAL per end — `MechanicalLock.HasGroove` = width > 0 ∧ depth > 0: Zone 3 declares an explicit 0 × 0 since ⚖️ 2026-09-18 (HW.26), the Zone-1 groove stays until HW.26 G1/G3, no ring is fitted as a backup on either end, and both sheet readers print «NO DIN-471 groove on this end» where none is cut; render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `tools/cad/src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + the capsule's SINGLE face-seal O-ring groove on the top face — depth · width · radii DERIVED from the `o_ring` block and the socket band shared with the radome (`CathodeFlange.ORingGroove*`; 00_07 HW.33 branch (а), applied 2026-09-14), nothing stored; the flange sheet draws it as geometry in both readers and its depth tolerance as loud absence |
| `tools/cad/src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + a LOCAL INTERNAL RIM BOSS (`Radome.Boss*`/`SealLand*`: socket band `lug + clearance` outside ⊥ seal land `gland width + 2·clearance` inside; rim cavity ≤ Ø15.57 at the 80 % gland fill — every term a MINIMUM, a ceiling HW.9 takes as an input, ⚖️ 2026-09-14) + the bayonet socket, cut in the boss's OUTER band only + PCB cavity; the rim is FLAT — the single O-ring groove is the flange's, derived from the `o_ring` block both manifests carry (gotcha #9 INVERTED — hollow is intended). ⛔ **ONE ratified-but-still-shipped divergence lives in this file:** the CAP is still a FULL HEMISPHERE where ⚖️ 2026-09-11 ratified a FLAT CROWN with an R5 edge fillet (rise 12.5 → 5.0, height over bark 25.5 → 18.0), and it waits on ⚖️ HW.30 (piezo placement), not on a budget. ⚠️ Applying it silently inflates `hollow_fraction`, because `Validation`'s reference solid still adds a hemisphere — recompute that formula in the same commit — and `bell_rise_mm`/`bell_radius_mm` must become DRIVERS, which today they are not. ⚠️ The raised COLLAR that carries the lugs at `Assembly.RequiredLugZMm` (20.5) is modelled on NEITHER part — its wall is set by nothing (no bayonet load model), and a placeholder would print on the flange sheet as a decision — so the socket keeps its L-slot shape (clipped to the outer band, pocket `socket band − skin` = 1.6 deep, skin 0.2) until that leg reshapes it: socket and collar are the female and male halves of one band. `verify radome` MEASURES the seal land solid over the full rim face (`SealLandSolidFraction`), the xUnit pins only derive it |
| `tools/cad/src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, `02_02 §4.4`) — bayonet datum via `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates; pure mate-math (xUnit) + render interference (`verify`) |
| `tools/cad/src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (smooth bore; hex + flange-shoulder deferred, bench-gated) |
| `tools/cad/src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, `02_02 §4.5`) — press-fit interference + insertion budget + span; reuses `Assembly.Build` + Zone-1 envelope; pure mate-math (xUnit) + render (`verify`) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts, porosity AND the FE stiffness ratio all drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify` (geometry) or `fea --sweep` / `fea --fit` (stiffness AND the Gibson-Ashby coefficients — a single row is an UPPER bound by construction, and the FITTED `C` itself still moves with the step (0.954 · 0.989 · 0.983 at period/16 · /24 · /32), so nothing is quoted without its convergence ladder).

**State** lives in `00_07` (HW.1 · HW.33 · HW.34 · HW.8 · HW.26), not here; memory keeps the router `[[project_picogk_code_as_cad]]` (⊕ its journal twin `[[log_picogk_cad]]` — the BODIES, with their numbers), and the curator lessons born in CAD sit in their class homes (applying a ratified verdict → `[[feedback_verdict_lifecycle]]`) · `[[project_anchor_bus]]` (bus router + the PEEK-liner trap, gotcha #0) · `[[project_coin_bakeoff_trl4]]` (the Ti-coin keystone this CAD feeds). This pointer was **missing** until 2026-08-08 — every sibling skill (`ssot-maintenance`, `ml-engineering`, `web3-pipeline`) carried one and this file did not, so CAD state was reachable only by someone who already knew it existed.

## Gotchas Not Obvious From Docs

**Bodies live in `gotchas.md` — open it before touching a generator, a CEM manifest, `draw`, `fea`
or `verify`.** Below is one generated line per gotcha: the line is the CARRIER, meant to stop you
mid-action; the mechanism, the incident and the bounds are in the companion. Numbering is
append-only (`0a` · `0b` · `4a` · `9b` are items of their own).

<!-- PICOGK-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

0. `tools/cad/cem/*.json` is the parameter SSOT, and its `liner 0.15 mm` is now a RATIFIED branch — but read why before you touch it
0a. «CEM json = parameter SSOT» is true only where the manifest SPEAKS — and `cem_canon_sync` guards exactly that half, so the silent half has no gate at all
0b. A manifest can be silent for a SECOND reason, and this one is worse than a default: the record has no SLOT, so the key you write EVAPORATES
1. Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`
2. `ImplicitRadialGyroid` is degenerate near r=0 — use a cartesian gyroid for a small part near its own axis
3. Run headless through `Library.Go(voxel, task, bEndAppWithTask:true)`, never `new Library()` — and CI still needs a display
4. Gyroid `wallParam` is a DIMENSIONLESS level of the gyroid equation, and the sheet and network branches read it differently
4a. «Porosity is voxel-dependent → MEASURE it» — the RULE stands, its suspected CAUSE was tested and REFUTED (2026-09-12, `00_07` HW.49)
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

<!-- /PICOGK-GOTCHAS-INDEX -->

## Common Tasks

- **Add a part / per-species SKU**: write `cem/<name>.json` (with a `kind`) + a generator in
  `src/SilkenCad/` + wire the `build`/`verify` switch in `Program.cs`; `dotnet run -- verify`.
- **Change anchor geometry**: edit `cem/anchor_zone1.*.json` (Ø, period, wallParam — and `bus_rod_diameter_mm`, which since 2026-09-18 declares the WELDED WIRE, an assembly part: the anode is printed with NO core and `Zone1Anode.InnerRadiusMm` returns 0 for every manifest, pinned by `AnchorTests.The_Printed_Part_Carries_No_Core`. The wire field still has to BE there — `Every_Shipped_Anchor_Cem_Declares_Its_Bus_Rod_And_No_Bore` reds on a manifest that omits it or carries a bore key, which would otherwise evaporate on parse).
  Geometry numbers are owned in `01_01 §5` + founder decisions in `00_07 HW.33`; **MEASURE
  porosity after** (gotcha #4). Render via `Zone1Anode.Anode` (the ctor route, gotcha #1).
  ⚖️ **Topology = `network` (ratified 2026-09-10, APPLIED 2026-09-11)** — every shipped `anchor_zone1.*`
  but `stepped` now declares it; `stepped` is a separate, already-decided THIRD branch (`ZonedGyroid`).
  🔴 **The live rule is that `wallParam` NEVER carries across a topology flip, and it is not cosmetic:**
  the param is a BAND on sheet (`|eq| < 0.5·w`) and a LEVEL on network (`eq < 0.5·(w−1)`), so the
  sheet-era 1.0 lands network at 50.2 % porous / **≈23 GPa formula-only under the canonical pair (lattice cube · AXIAL · `/32`: `C` 0.983 · `n` 2.242, ⚖️ ratified 2026-09-18, 01_01 §5.2 — an estimate that must be marked as one; the radial axis has no formula pair at all) — canon reports apparent stiffness per axis (×0.79 axial / ×0.56 radial, re-measured 2026-09-18 on the welded branch), and the 13–15 GPa requirement was withdrawn 2026-09-17, so never quote a bare GPa figure as a target
  (`01_01 §5.2`); the «~27» that stood here was the retired `C` = 1 · `n` = 2** — *stiffer* than the branch it replaced. Re-solve
  against the porosity target FIRST. Measured 2026-09-11: the network curve is `porosity ≈ 66.4 − 16.2·w`
  and it is a function of the LEVEL, not of the period — so one value, **0.10**, hits 65 % on all five
  species SKUs (64.7–65.0 %), contrary to the tracker's assumption that each SKU needs its own.
  🔴 **Two traps this branch arms, both silent, both bought here.** (a) The `graded_porosity` SKU grades
  the wall itself, and on network its rim needs a NEGATIVE level (−0.46 → 73 % porous); the old
  `GyroidWallParamRim > 0f` sentinel swallowed that back to the core value, i.e. the manifest would state
  a gradient and the geometry would be constant, with nothing red. The field is nullable now — but the
  general form is the lesson: **a `> 0` sentinel encodes «≤ 0 is meaningless», and a topology change can
  make ≤ 0 ordinary.** (b) The CLI `scan` swept `wallParam` from 0.2, so the ratified working point 0.10
  sat OUTSIDE the sweep and the command would have answered "no working window" on a sound part; the
  bounds are topology-dependent now (measured network window `[−0.50, 0.60]`).
  📐 Prices, measured per SKU rather than quoted: specific surface sheet→network **1.84–1.89×** (the canon
  «~2×»), and sub-floor solid metal **1.5–49.7 % → 0.2–1.3 %** — the print-floor divergence the sheet
  branch carried was the thin wall, and network has none.
- **Welded bus wire (`01_01 §1.4` + `§3` step 1b, HW.1/HW.34, SHIPPED)**: `bus_rod_diameter_mm` declares the WIRE. ⛔ **It is NOT printed with the anode** — ⚖️ founder 2026-09-18 applied the welded branch in CAD: the part has no core (lattice to the axis), `Zone1Anode.BuildMonolithic`/`BusRod` and `fea --with-rod` are REMOVED, and the wire body lives in `AxialStack` starting at the anode's TOP FACE (`BusWireBottomZMm`), where the weld seam and the cantilever root coincide. The golden baselines and the sub-floor shares were re-measured the same day (`01_02 §1.3`); every part-level FEA cache (`.d7` · `.d10` · `.d32`) is on the welded body since 2026-09-18, while `printed_core_branch` / `with_rod` are frozen evidence. ⚠️ **Why the route matters even though the CAD now only models the RESULT:**
  the ratified fabrication is a WELD (⚖️ 2026-09-10 — an as-printed rod carries `ENDURANCE_OVER_YIELD ×
  AS_PRINTED_DERATE`, a welded cold-drawn wire does not), and until 2026-09-18 the generator drew the
  rod as a printed core, i.e. an STL of the branch that verdict removed. Consequence you will hit: the rod's tolerance and `Sa` come from a WIRE spec canon does not
  carry, not from an LPBF surface. ⚖️ **RATIFIED 2026-09-12: both are a VENDOR INPUT entering through the Validation Gate (`00_06 §0`), not a number we pick** — so this is an RFQ answer waiting, no longer an open judgment (`00_07` HW.34). ⛔ And the half that verdict REJECTED is the one that will tempt you back: "a drawn wire is smooth, so liner wear is solved" — the specific wear rate has no number and no literature figure anywhere in this tree (since 2026-09-12 `55` §`wear_budget` bounds the rate the pair may have, which is a budget, not a measurement), and FMEA `#21` HEADS the register since the 2026-09-18 S-sweep — scores live in `docs/protocols/hardware/fmea_fmeca_register.md` §1, never here. The CEM still has no field for either. ⛔ `Zone1Anode.BuildMonolithic` = `Anode` + `BoolAdd(BusRod…)` was the printed-core build and is GONE (2026-09-18); `Zone1Anode.Build` is the gyroid alone. 🔑 **Porosity stays a property of the gyroid**
  (`Anode` + the FULL cross-section envelope, `InnerRadiusMm` = 0 since 2026-09-18, HW.1 welded branch) — porosity
  is measured against the whole Ø; the wire is not in the part, so `verify anchor_zone1` measures no rod (the
  rod-fusion measure in `ReportAnchor` left with the branch).
  ⊕ **Since 2026-09-13 that is the ONE inner radius in the tree:** `build`, every topology metric
  (`Connectivity.SampleAnchor`, and through it the as-printed opening and the wall scan), per-shell porosity
  (`Validation.ShellBoundariesMm`), the FE sampler and the anchor drawing all read `Zone1Anode.InnerRadiusMm`.
  Pin `AnchorTests.Every_Anchor_Reader_Samples_The_Inner_Radius_Build_Cuts` judges the three SAMPLERS (topology · FE ·
  per-shell) against the radius `build` cuts — never against another reader, so two readers wrong the same way still
  red; the drawing calls the same function but is not in that pin. Before it,
  topology sampled r ≥ bore/2 and dropped a ring the printed part carries: invisible on six SKUs (Δ ≤ 0.04 pp,
  inside golden tolerance) and past it only on `stepped` — i.e. a golden gate alone would have seen the defect
  on one SKU of seven.
  Cathode keeps its channel (`mechanical_lock.zone3`/flange bore); anode shank `bore→0` (solid). F3 audit =
  `AxialStack.BusRodClears` (rod + 2·liner **<** channel), and since 2026-09-12 **F4
  `AxialStack.LinerCoversChannel`** — the liner must cover the channel END TO END, not merely fit it by
  diameter. ⛔ F4 exists because F3 declares that blindness and cannot close it: a tube SHORTER than the
  channel passes F3 green while leaving bare cathode metal against the bus at one end. Its axial extent
  comes from `bus_liner_protrusion_mm` (⚖️ 2026-09-12: the lower end protrudes ≥ 1.0 mm into the PEEK
  gap, so the bore EDGE meets the tube's flank instead of its end face). ⚠️ **The comparison is STRICT since 2026-09-11 and
  the channel is Ø1.35, not Ø1.3** (00_07 HW.34, clearance verdict): at the old trio 1.0 + 2×0.15 ≤ 1.3 the
  gate passed at ZERO nominal clearance, i.e. blessed a tube whose outer Ø equals the bore. It now fails
  exactly that, pinned by `Zero_Nominal_Clearance_Is_Not_A_Pass__The_Pre_Verdict_Channel`. ⛔ Its declared
  ceiling did NOT change: it still judges NOMINALS, and the diametral band of the machined bore is an open
  vendor question — green here is not proof that a real pair mates.
- **Graded gyroid (v2, SHIPPED)**: own SDF, **NOT** LEAP `ImplicitModular` (`FunctionalScaleTrafo`
  is a hard-coded Z-demo, not radial; LatticeLibrary upstream is DORMANT — our pin IS `HEAD main`, so
  re-check it by `git ls-remote`, never by age; the one that IS behind is `LEAP71_ShapeKernel` — skill
  `dependency-update`). Three CEM-driven axes
  in `Zone1Anode`: `GradedCartesianGyroid` (continuous period+wall taper) + `ZonedGyroid` (stepped
  zones). Pick by goal — continuous-gentle (smooth, ≤~0.8× period ratio), `GyroidWallParamRim`
  porosity gradient, or `topology: stepped` for a STRONG ~2× pore contrast — ⛔ **µ-LPBF only since ⚖️ 2026-09-17: `stepped` is NOT an SLM pick** (71 % of its lattice metal sits below the 0.2 mm floor BY CONSTRUCTION; revisit only if a vendor declares ≤ 0.1 mm). **MEASURE** porosity.
- **Mechanical-lock barbs (`MechanicalLock.cs`, SHIPPED)**: asymmetric ratchet `R(z)` on the Ti shank
  — solid `BaseCylinder().voxConstruct()` + thin barb-ridge `BoolAdd` + a groove-ring `BoolSubtract` ONLY where
  `MechanicalLock.HasGroove` (Zone 3 = explicit 0 × 0 since ⚖️ 2026-09-18, HW.26; the Zone-1 groove stays until HW.26
  G1/G3) + a central bore (`0` ⇒ SOLID anode shank, no channel — the bus wire is welded on the anode's top face,
  `01_01 §1.4`; `Ø1.35` ⇒ the cathode channel the wire threads) (gotcha #9 — never the SDF ctor for the solid). Tooth is over-specified in `01_01 §4.3` → keep
  α/β + h, DERIVE base = h·(cotα+cotβ), MEASURE in `verify`. Self-support holds only for a SEPARATE print laid
  gentle-ramp-down (`01_01 §4.3 A`; `01_02 §1.6` says only tip-down); where a groove IS cut it takes real DIN-471 shaft dims (not the off-spec canon 0.8×0.6), no ring is fitted as a backup on either end, and a sheet whose end carries none prints «NO DIN-471 groove on this end». In the
  lock's own frame the shallow α ramp faces z = 0 — the end that enters the PEEK first — on BOTH ends, with no
  direction knob (gotcha #15); the Zone-1 anode's frame runs the other way (z = 0 = tree side), so an integrated
  shank is PLACED by rotation; on the INTEGRATED Zone-1 body «tip-down» puts the steep face down (20°) — open, `00_07` HW.26 G4.
- **Connectivity / verification (ARCH.25)** ⚠️ (this bullet said «validation» until 2026-09-12; canon `01_02 §6` now names it what it is — CODE VERIFICATION, two independent routes to one topological fact. Validation needs the physical experiment we have not run): `Connectivity.cs` samples the CEM SDF → 3-phase grid →
  6-conn flood-fill → open-pore (Archimedes) / percolation (EAAE flow-through) / solid-island (AM +
  electrical) / closed-pore (trapped-powder) / specific-surface. Pure-managed → fast display-less xUnit. Two-phase resolution split:
  **pore** OK at the coarse step, **solid** needs ~period/24 (gotcha #8 — the labyrinth COUNT converges
  later than the island FRACTION). The `verify` gate adds
  open≥95% · solid-disc≤2% · percolate axial+radial. Topology-agnostic by construction — which is why it
  survived the sheet→network switch unchanged (the HW.33 axis it once fed is closed).
- **Topology-convergence ladder (`converge`, SHIPPED 2026-09-18, `00_07` HW.51)**: `dotnet run -- converge
  cem/<anchor_zone1.x>.json --divisors 24,32` samples the same connectivity metrics at each divisor of the finest period
  and writes a VERSIONED cache under `tools/cad/cache/topology/` (unlike `out/`, a run has a diff). A probe, never a
  verification — no golden, no OK/FAILED; a rung clamped onto the adaptive floor prints «SAME GRID … proves nothing» and
  a SKU whose rungs all land there prints «NOT A LADDER». Pin `AnchorTests.Every_Committed_Convergence_Ladder_Was_Measured_On_Todays_Sampler`
  recomputes the sampler step from the CODE. ⚠️ Its ceiling is the trap: the cache name carries the SKU only and the pin
  judges only the step, so a run with other `--divisors` silently replaces the committed ladder — pass the committed
  divisors and read `git diff tools/cad/cache/topology/` before committing (gotcha #14's class). Numbers → the cache /
  `00_07` HW.51, never here.
- **Capsule-end assembly (`Assembly.cs`, SHIPPED)**: brings Деталь 3 ↔ Деталь 4 into one frame at the
  bayonet datum (radome lock-groove ↔ flange lugs) via `MeshUtility.voxApplyTransformation` (lift; the
  per-part `Build`s stay untouched) and MEASURES the residual mismatch (radial / bayonet-Z / RF) + models
  the skirt/inboard MATE-Ø candidates. An AUDIT table — `verify` exits on a broken render only; the
  mismatch numbers are asserted by pure xUnit. Canon `02_02 §4.4`. ⚖️ **The reconcile is NOT one bench job:
  the RADIAL half was ratified 2026-09-10** (Ø25 stays, a local internal rim boss carries socket + seal land,
  `skirt` withdrawn because it deletes the sealing face), **and the bayonet-Z half was RATIFIED 2026-09-11**
  (`02_02 §4.4`: lugs on a RAISED COLLAR above the sealing face) — because the mismatch is `t/2 + lockGrooveZ`,
  two positive terms (it was THREE — the O-ring face gap 1.424 was the third, and it is ZERO under branch (а), applied
  2026-09-14: the rim is a hard datum on the sealing face, `ORingGapMm` is gone, the mismatch reads 5.0 because a
  term LEFT the chain, not because a value moved), so no assignment of the frozen dims reaches zero and the lug
  needs a Z of its own (`Assembly.RequiredLugZMm` = 20.5). ⊕ The two "separate" equations share `Rf + mismatch =
  cavityH`: lowering `lockGrooveZ` pays into BOTH, `cavityH` into RF alone — ⛔ but «raise the cavity» is a REMOVED
  branch: the ratified flat crown moves the headroom the other way, and the RF floor is set from BELOW by the board
  stack. ⚖️ 2026-09-14 «вхід»: the rim BOSS is APPLIED under the Ø15.57 ceiling and HW.9 takes that ceiling as an
  input (the seal mate is pinned: `Assembly.SealLandBacksTheGroove`, one slot clearance of land each side, strict);
  the collar waits on a wall nothing sets, the crown on ⚖️ HW.30; HW.8.8 is the bench leg that follows.
- **Full axial stack (`AxialStack.cs`, SHIPPED)**: the SECOND integration artifact — brings ALL FOUR zones
  (anode → Zone-2 sleeve → flange → radome) into one axis and MEASURES the **press-fit** interfaces the
  capsule-end never touched: Zone1↔2 line-to-line (real +interference = the press-fit band on bench — the H7/r6 read carried under an s6 label; no table class — the band is solved from the Lamé window, ⚖️ 2026-09-18, `00_07` HW.3, its inputs are open, and today's MIN lies below that window's floor) · **Zone2↔3 =
  −1.0 mm = the Ø9-in-Ø11 clearance = F1, shank Ø placeholder → HW.8.9** · insertion budget · span. AUDIT
  table; render uses the Zone-1 **envelope** (solid Ø11 — a press-fit cares about OD, not porosity; also
  keeps the 0.2 mm voxel safe). Reuses `Assembly.Build` + `voxApplyTransformation`. Canon `02_02 §4.5`.
  🔑 **`BasePipe`/`BaseCylinder` Z-origin = `[0, L]` from the frame** (grows along +localZ; verified in LEAP
  `Frames.cs` — NOT centred), so stack lifts are absolute; the render overlap sleeve∩capsule is the flange
  SHOULDER on the sleeve top face, not the shank (the Ø9 floats in the bore).
  ⊕ **The Zone-1 insertion is judged against its OWN lock (2026-09-13, `00_07` HW.26 G1):** the stack NAMES the lock by
  file (`zone1_lock_manifest`) and never copies its numbers — a nested `MechanicalLockCem` fills absent fields from defaults
  whose contact zone and groove ARE the Zone-1 lock's, so a wrong or empty copy would print the right window (hence the
  `kind` check in `AxialStack.Zone1Lock`). One home: `MechanicalLock.InsertionWindowMm`; `verify` prints it beside
  `zone1_insertion_mm` and flags an insertion outside it. 🔑 **Pin a detector with the value HANDED IN, never read from
  the default** — a pin asserting that the shipped placeholder stays outside cements the defect and reds the day G1 is fixed.
- **Generate an engineering drawing (`Drawing.cs` / `draw`, SHIPPED Phase 0+1)**: `draw <cem>` emits
  **SVG (human) + DXF via netDxf (factory, opens in AutoCAD/Fusion)** — no PDF (scoped in research, never
  built); ⚠️ read gotcha #11 BEFORE touching notes/tolerances — pure-managed, no Library.Go,
  consuming the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text; `DrawingStandard` ISO/ASME
  param). Drawing carries fits, GD&T datums, post-process + coating-restriction notes, lattice-spec.
  ⚠️ **«Lamé-µm, NOT a blind ISO-286 lookup» is the canon REQUIREMENT (`01_01 §4.2`), and the shipped band
  does not meet it** — `zone2_sleeve.json`'s 5–34 µm is the ISO 286 table (`tools/in_silico/lib/constants.py`), which Lamé
  merely consumes to get a contact pressure. The generator used to paper over the gap with a hard-coded
  «(Lamé, E_PEEK-aware)» suffix; that invented provenance is gone (gotcha #11), and the engineering verdict is
  taken — no table class, the band is solved from the Lamé window (⚖️ 2026-09-18, `00_07` HW.3; its inputs are
  open). **Do not read this bullet as «the drawing carries Lamé µm» — it carries what the CEM says, and the CEM
  says ISO 286: today's 5–34 µm is an H7/r6 read whose MIN lies below that window's floor, so the number will
  move.**
  ⛔ **Shipped kinds are NOT listed here** (this passage carried a roster and it went stale the day a kind
  landed) — read `Program.Draw`'s `switch`; phasing and the kinds deliberately NOT drawn, each with its
  ground, live in `tools/cad/docs/drawings_program.md §7`. A kind is meant to carry the shipped-CEM DXF
  round-trip and, if published, a gallery pin — check per kind rather than trusting this sentence, and do not
  count the sha-256 pin as a round-trip: it proves WHICH manifest was drawn and nothing about what the sheet
  carries, so a kind reached only by it ships its notes and fits unverified in the factory reader (⛔ test COUNTS
  quoted nowhere — the roster is `DrawingTests.cs`).
  🔴 **The anchor sheet is the one whose CONTENT is load-bearing rather than its geometry:** `draw
  anchor_zone1` exists to carry the `01_02 §3.6` coating zone-map, whose Zone-1 rows hold OPPOSITE
  permissions (gyroid wall in sap: every dielectric forbidden ⊥ periphery in callus: Zn-HAp allowed) and
  whose dividing surface is in no manifest and is not derivable from the geometry. The sheet therefore
  REFUSES it out loud in both readers, pinned. ⛔ And the lattice is a CALLOUT, never a contour: an honest
  SDF cross-section is available pure-managed and canon `01_02 §6` forbids it anyway (over-drawing a PBF
  lattice promises a precision nobody measures) — `drawings_program §4` used to prescribe one and was
  reconciled, so a future «let's sample the SDF» has to argue with canon rather than drift.
  NORM (why a drawing is derived from the CEM, what it must carry, the loud-absence rule) = canon [`01_02 §6`](../../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md);
  research + phase roster = `tools/cad/docs/drawings_program.md`.
  🔴 **`docs/images/cad/*.drawing.svg` is a SECOND artefact and nothing re-runs the gallery for you.** It
  is committed and opens straight from GitHub (a blob-rendered SVG) — i.e. the drawing outsiders see —
  and it sat on the pre-2026-08-28 output for weeks after that fix landed in code, publishing exactly the
  dropped/invented lines the fix removed. ⚠️ **`wiki:sync` does NOT carry it, and writing that it does was
  a FABRICATED mechanism** (measured 2026-09-09): `lib/tasks/wiki.rake` syncs only the canon `NN_NN_*.md`
  and copies an image only where a doc EMBEDS it as `![…](…)`; no canon doc embeds these, so that set is
  empty. Want them on the wiki — embed them in a canon doc first. Change `Drawing.cs` or a CEM ⇒ re-run
  `tools/cad/scripts/render_gallery.sh` (or at least its DRAWING loops — ⛔ **read the loops, never a
  count**. This passage has now been wrong TWICE by its own counting: "its two `draw` lines" was wrong by
  half, and the "FOUR targets" that replaced it was wrong again within two days when the anchor card and the
  Zone-2 sleeve landed. 🔑 The second miss is the instructive one, because the sentence carrying the count
  was the very sentence forbidding counts — an example does not get an exemption from the rule it
  illustrates, and a roster beside a growing script is the volatile counter in prose form) and commit the SVGs. A pin now reds on the CONTENT drifting apart
  (`Published_Gallery_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame`) and, since 2026-09-13, on
  MANIFEST IDENTITY: every sheet prints `cem_sha256` (prefix in the title block → FOOTER, full hash in the footer
  and the DXF), so any byte change to a published manifest — a note or a trailing newline included — reds its
  gallery row until the drawing loops are re-run. ⛔ Declared ceiling: not the sheet's layout bytes, not its
  `rev` stamp, and the PNG renders beside it are pinned by nothing.
  🔴 **`cemSha256:` is an OPTIONAL parameter threaded through one `case` per kind in `Program.Draw`, so the
  compiler will not ask a new kind to pass it** — the carrier is `Every_Drawn_Sheet_Names_The_Sha256_Of_The_Manifest_Bytes_It_Was_Drawn_From`,
  which runs `Program.Draw` itself. Measured: unwiring ONE case reds only that row while every pin that calls
  `Drawing.X` directly stays green. 🔑 A test that hands the emitter a value of its own making proves the
  emitter, never the wiring — so adding a kind means passing `cemSha256:` to BOTH halves.
- **Render / section for presentation (`render`/`section`, SHIPPED)**: `render <cem>` = a PicoGK native-viewer
  screenshot (gold Ti-metallic material); `section <cem>` = a −X cutaway, for the inside `ColorFloat` alpha can't
  show: `section anchor_axial_stack` shows the welded wire (gold) from the weld seam on the anode's top face;
  `section anchor_zone1` = the lattice alone since 2026-09-18 (the committed section PNGs still show the retired
  core — unpinned, like every PNG here). Display-gated (gotcha #10); output → `out/*.png` (native TGA → `sips`). The
  presentation gallery `docs/images/cad/` is NOT SSOT (`tools/cad/scripts/render_gallery.sh` rebuilds it)
  — ⚠️ but see the drawing bullet above: **not-SSOT is not a licence to lag**, and the PNGs there have no
  pin at all, so a stale render is invisible to everything.
- **Measure apparent stiffness** — `dotnet run -- fea <cem> --sweep` (part) · `fea --ladder` (the same lattice as an n-cell cube, the material-scale control) · **`fea --fit` (the Gibson-Ashby `C` and `n` fitted over a `wall_param` sweep — TWO specimens on ONE flag: no cem argument ⇒ the lattice cube, a cem argument ⇒ the shipped part (the lattice to the axis), `fea cem/anchor_zone1.pine.json --fit --step-div 10 --walls -0.40,-0.20,0.00,0.20,0.40,0.60` — the part form REFUSES without `--walls` since 2026-09-18 (gotcha #14))**. Reported as a fraction of `E_solid`, because the Zone-1 alloy is bake-off-gated (00_07 HW.24) and the candidates span 80–186 GPa. ⛔ A single row is an UPPER bound (staircase boundary + fully-integrated hexes, both stiff-biased), so never quote one without its sweep; and the subject is the PRINTED part — the lattice to the axis. ⛔ `--with-rod` was REMOVED 2026-09-18 with the printed-core branch (⚖️ 2026-09-10, applied 00_07 HW.1): it measured a body the factory never receives, and canon quoted its «+9 % axial» as a property of the part. ⚠️ Every part cache in `cache/fea/` is on the welded body since 2026-09-18 (`.d32` last, 8 h 20 m Release); `printed_core_branch` / `with_rod` are frozen evidence, and the lattice cube and the ladder are unaffected — they never had a core. Trust `with_bus_rod` in the file over this line. 🔴 **`C` and `n` are MEASURED since 2026-09-12, not assumed** — on the lattice cube and on the shipped part, per axis and per step, and the numbers live in the `01_01 §5.2` table only (they moved once already, when the welded branch took the core out of the specimen) — **so the textbook `n = 2` is retired AXIALLY and the member that was wrong there is the EXPONENT, not `C`.** 🔴 **And WHICH member is wrong is a property of the AXIS: the radial fit of the same part (`--with-radial`, period/10) keeps `n` near 2 while `C` falls well below 1 — on the load-bearing axis the exponent is textbook and the coefficient departs** (`01_01 §5.2`). ⛔ `--with-radial` is REFUSED on a step that does not divide the diameter (an odd divisor on Ø11): the grid gains an empty column and the radial load centre walks a quarter step off the axis (`VoxelFea.RadialLoadCentreOffsetMm`); the axial fit is unaffected and still runs there. ⛔ **On a CONSTANT-period part every `--step-div` is PHASE-LOCKED** (gotcha #16 — the divisor takes the step from the period): sweep such a part with `--step-mm` (a step from the diameter, not from the period), and expect the verb to refuse a sweep whose walls sample to one grid. ⛔ **Never compare a single-density `C` across geometries: the SAME cube reads 0.71 · 0.80 · 0.77 at 16 · 24 · 32 steps, i.e. the full width of the «cube↔part gap» canon used to call non-physical. Compare FITTED pairs or nothing.** (The cube is locked by construction, so part of that wander is plausibly its porosity staircase — not separated from the mesh-stiffness term, and not measured apart.) ⛔ **And this verb does not produce what a physical test returns by default:** ISO 13314's comparable quantity is the **elastic gradient** — the secant of an UNLOAD/RELOAD hysteresis loop between 20 % and 70 % of plateau stress — never the quasi-elastic gradient, whose role in the standard is to locate the strain zero; so a printed-specimen order without an unloading cycle comes back with nothing to compare against, and any comparison must name a POINT on the curve. ⊕ **Print thickening is a SENSITIVITY, never a body: `fea <cem> --dilate downskin|iso`** — the offset is a FACE displacement (segment LENGTH along +BD in the part frame · ball RADIUS, so a ligament gains 2R); a shifted sample takes metal only from inside the part body while the origin is never clipped, which is what lets the zero row reproduce the pinned `/12` row bit for bit; caches are `dilation_sensitivity.*`, one file per row. Numbers, the literature check and the declared ceiling → `01_01 §5.2`; the table is machine-held by `ruby scripts/fea_canon_sync.rb` (HARD in `docs.yml`; which layer holds which table → read the script itself, never a number here).
- **Check resolution adequacy** — every declared thickness/gap against the voxel its own assembly asks for, `2·voxel` represented / `4·voxel` volume-honest. Hard carrier `ResolutionTests`, operator line inside `verify`. 🔑 Walks the PARSED RECORD TREE: a composite manifest declares a handful of numbers and inherits dozens of `Cem.cs` defaults written for a PART voxel — that inheritance is the defect class, not a detail.
- **Local-verify** (`export PATH="$HOME/.dotnet:$PATH"` first — the SDK is NOT on PATH, and «dotnet is not installed here» has already been asserted falsely once, 2026-09-10): `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1) → `dotnet run -- draw cem/<x>.json` (SVG+DXF → out/) → `dotnet run -- fea cem/<x>.json --sweep` (pure-managed like `draw`; ⚠️ it writes into the COMMITTED `cache/fea/`, unlike `out/`, so a run has a diff)
  → `dotnet test`. CI = enterprise 2-job `cad_smoke.yml` (logic = Linux pure-xUnit hard [incl. draw/DXF]
  + render = macOS build-hard + verify best-effort, Library.Go 139 headless).
  🔴 **`dotnet run` builds DEBUG by default, and for an FE run that is a ×4.1 tax — measured, not assumed** (2026-09-15, on the pinned `.d7` part fit: **73 s at `-c Release` against 298 s in Debug**, same machine). ⛔ The reason it is safe to take: the Release run reproduces the committed cache **bit for bit** on every axial cell and on `C`/`n`, so the config is a cost axis and not a numeric one — verified by re-running `.d7` into a copy and comparing field by field. 🔑 **Where it actually bites is the ESTIMATE, not the run:** the «~1.5 доби CPU» that priced the `--step-div 32` leg in `00_07` HW.33 was extrapolated from a Debug probe, and the real Release run took **7 h 50 m**. So a cost quoted from a probe carries the probe's BUILD CONFIG inside it, invisibly — when you price a long run from a short one, say which config you measured. ⊕ For a run of hours: `nohup caffeinate -i` (a sleeping Mac stops it), and run the binary from a COPY (`cp -R src/SilkenCad/bin/Release/net9.0/. out/<name>_bin/`) — a parallel agent's `dotnet build` in this tree would otherwise swap the DLLs under a live process. The cache is written only at the END; the per-wall rows print as they solve, so redirect stdout to a durable log or a crash at hour six leaves nothing.
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink (vendored LEAP source, kept out of owned code).
