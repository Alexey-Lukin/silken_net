---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin in-vitro coupon, the Zone-1 gyroid anode, the CartesianGyroid SDF, the PEEK Radome — shipped, `dotnet run -- build cem/radome.json`) and the CEM (Computational Engineering Model) manifests that drive them. Knows the non-obvious gotchas — render lattices via `new Voxels(IImplicit, BBox3)` + BoolIntersect NOT voxBounding.voxIntersectImplicit (uncatchable native OpenVDB abort at fine voxel on thin bored parts), headless `Library.Go(voxel, task, bEndAppWithTask:true)` not the stale v1.6 `new Library()`, ImplicitRadialGyroid axis-singularity → cartesian gyroid, dimensionless gyroid wallParam + voxel-dependent porosity (MEASURE it), the voxel-resolution floor, ImplicitUsings-ENABLED for vendored LEAP source — and the local-verify discipline (`dotnet run -- verify` → metrics.json, exit 0/1). ALSO the engineering-drawing tract: `draw <cem>` → SVG (human) + DXF (factory, GD&T/CMM acceptance) built from the CEM `tolerances`/`notes` blocks, the rule that an absent field prints `NOT SPECIFIED IN CEM` rather than a plausible default, the two readers (SVG clips, DXF does not), and the committed gallery under docs/images/cad that lags its generator unless you re-run it. Routes to 01_02 §6 (PicoGK stack + Noyron methodology + the drawing NORM) + 01_01 §5 (anchor geometry) + tools/cad/README, does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"add the radial pore gradient\", \"build the Ti-coin STL\", \"make a factory drawing / DXF\", \"add a surface-finish or coating note to a CEM\", \"set up the .NET CAD project\"."
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
| `tools/cad/src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw <cem>`): **SVG (human) + DXF via netDxf (CAD-native factory deliverable, opens in AutoCAD/Fusion)** — no PDF (never built; `drawings_program §3`). Pure-managed string/entity build, no Library.Go. Consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). Shipped kinds = `ti_coin` + `cathode_flange` + `mechanical_lock` (HW.26, 2026-09-09 — Zone-1 anchor end + Zone-3 flange end, one generator/CEM `kind` shared by both manifests; §7 rest deferred — `tools/cad/docs/drawings_program.md`). ⚠️ gotcha #11 |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) + reuses LEAP `Measure.fGetSurfaceArea` |
| `tools/cad/src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-conn flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit |
| `tools/cad/src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb + DIN-471 groove SDF on the shank (Zone-1 solid monolithic / Zone-3 channelled); render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `tools/cad/src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + O-ring groove |
| `tools/cad/src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + bayonet socket + PCB cavity + O-ring groove (gotcha #9 INVERTED — hollow is intended). ⛔ **TWO ratified-but-still-shipped divergences now live in this one file, and applying either alone re-introduces the other.** (1) The CAP is still a FULL HEMISPHERE: ⚖️ 2026-09-11 ratified a FLAT CROWN with an R5 edge fillet, dropping the rise 12.5 → 5.0 and the height over bark 25.5 → 18.0. ⚠️ Applying it silently inflates `hollow_fraction`, because `Validation`'s reference solid still adds a hemisphere — recompute that formula in the same commit — and `bell_rise_mm`/`bell_radius_mm` must become DRIVERS, which today they are not. (2) That rim groove is RATIFIED AWAY and still shipped — ⚖️ 2026-09-10 put ONE groove in the flange (1.344 mm) against a FLAT rim; the two opposing 0.9 grooves still cut here give a squeeze of **−1.1 %**, i.e. the shipped pair does not seal. Do not treat it as intended geometry, and do not "fix" it by tuning one depth: with the rim as a hard datum the bayonet stops setting Z, so it is a CHAIN change (`00_07` HW.33) |
| `tools/cad/src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, `02_02 §4.4`) — bayonet datum via `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates; pure mate-math (xUnit) + render interference (`verify`) |
| `tools/cad/src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (smooth bore; hex + flange-shoulder deferred, bench-gated) |
| `tools/cad/src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, `02_02 §4.5`) — press-fit interference + insertion budget + span; reuses `Assembly.Build` + Zone-1 envelope; pure mate-math (xUnit) + render (`verify`) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts + porosity drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify`.

**State** (what is built / open ⚖️ / curator lessons) lives in memory, not here: `[[project_picogk_code_as_cad]]` · `[[project_bus_monolithic_onehome]]` (bus topology + the PEEK-liner trap below) · `[[project_coin_bakeoff_trl4]]` (the Ti-coin keystone this CAD feeds). This pointer was **missing** until 2026-08-08 — every sibling skill (`ssot-maintenance`, `ml-engineering`, `web3-pipeline`) carried one and this file did not, so CAD state was reachable only by someone who already knew it existed.

## Gotchas Not Obvious From Docs

0. 🔴 **`tools/cad/cem/*.json` is the parameter SSOT, and its `liner 0.15 mm` is now a RATIFIED branch — but read why before you touch it.** For months that number silently elected PEEK while [`01_01 §1.4`](../../../docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md) still called the implementation open: Parylene ~10 µm and TiO₂ ~0.1–10 µm cannot reach 0.15 mm, so a frozen dimension had decided an undecided question. ⚖️ **Closed 2026-09-10 in PEEK's favour — the liner is STRUCTURAL — and its STRUCTURAL half was RE-OPENED 2026-09-10** (`00_07` HW.34). The ground was «without lateral support not one of the six bake-off alloys reaches infinite fatigue life at the canon rod Ø1.0», and that ground is an AS-PRINTED number: `55_bus_mechanical` derates endurance by `AS_PRINTED_DERATE`, so the rod-fabrication verdict of the next day (a welded cold-drawn wire) doubles every safety factor. 🔴 **Measured 2026-09-11, and the doubling does NOT clear all six: it clears FOUR** — Ta 0.71→1.41 and CP-Ti 0.98→1.96 leave predicted failure and still sit under the SF-2 line. ⛔ And the model is a homogeneous cantilever with no weld seam, so the ×2 describes the WIRE, not the JOINT. ✅ **RE-JUDGED the same day (⚖️ founder 2026-09-11): the liner stays STRUCTURAL, and the whole fatigue ground was RETIRED rather than narrowed.** Both `L_FREE_*` columns are FREE cantilevers — no wall anywhere — while the rod threads a Ø1.3 bore, so at the 140 µm play a 10 µm film leaves, the rod takes up the play and **bears on the wall inside the bore on every µ the script sweeps**. An unsupported SF is therefore a number for a configuration that does not exist. What carries instead is WEAR: the same contact makes rubbing geometrically forced, and a 10 µm film is being asked to be a bearing in a blind L/D ≈ 13 bore whose wear-through is a ~0.5 V anode↔cathode short. 🔑 **Two portable halves.** (a) **Before quoting an idealised SF, ask what the idealisation ASSUMES AWAY** — here a wall the real part has; a free-cantilever number is not conservative when the omitted feature changes the regime rather than the magnitude. (b) The thermal sense here is **INVERTED** relative to the Zone1↔2 press-fit the corpus models: PEEK is the INNER part, so cooling shrinks it AWAY from the Ti wall (~2 µm diametral over 40 K), where in Zone1↔2 cooling grips harder. **The INSULATION half was never in dispute.** 🔑 **What survives as the lesson, and it is the reason this entry stays:** the contradiction lived in the CANON PROSE, and the manifest was the symptom — patching the JSON toward another branch would have broken the `AxialStack.BusRodClears` F3 gate (rod + 2×liner ≤ channel) instead of settling anything. ⚠️ And F3 is `≤`, so `1.0 + 2×0.15 = 1.3` passes at ZERO nominal clearance: the gate proves the liner FITS the arithmetic, never that the assembly goes together. Clearance allocation and the rod side are open legs, not gate findings.

0b. 🔴 **A manifest can be silent for a SECOND reason, and this one is worse than a default: the record has no SLOT, so the key you write EVAPORATES.** `Cem.Parse` runs without `UnmappedMemberHandling.Disallow`, so an unmapped member is dropped without a word — and until 2026-09-11 `AnchorCem` (every `anchor_zone1.*`) and `RadomeCem` had **no `Notes` property at all**. A `notes` block written into those manifests would have parsed cleanly, rendered nowhere, and read as done; the tracker leg that asked for it (`00_07` HW.1) described the gap as «the manifests do not carry notes», which is the symptom, not the mechanism. ⊕ The tell that this is a distinct shape from 0a: there a WRONG value is in force, here NO value exists and nothing says so. 🔑 **Reflex before writing any new CEM field: grep the record in `Cem.cs` for the property FIRST — a JSON key with no matching property is not a small mistake, it is an invisible one.** ⚠️ And the same absence hides in the opposite direction: `Drawing` renders a FIXED field set, so a field the record holds but the generator's kind never draws is equally mute. ⛔ Carriers, since neither is gated: the notes are pinned present by `AnchorTests.Every_Shipped_Anchor_Cem_Declares_Its_Coating_Restriction` — declared ceiling PRESENCE, never correctness — and `draw anchor_zone1` / `draw radome` / `draw zone2_sleeve` still do not exist, so those notes are a SOURCE with no carrier (`00_07` HW.1). ⊕ Worth carrying from the same pass: the production ORDER of `01_02 §1.3` (print+HIP → hot press-fit → EAAE → bake) means the press-fit shank surfaces are inside the PEEK joint BEFORE etching, so the dual-scale Sa/Sv spec does not reach them and a coating there is a FIT problem (2t of interference), not a DET one.

0a. 🔴 **«CEM json = parameter SSOT» is true only where the manifest SPEAKS — and `cem_canon_sync` guards exactly that half, so the silent half has no gate at all.** Where a manifest omits a field, the effective geometry is the **`Cem.cs` record default**, and nothing binds that default to canon: the guard reads `cem/*.json`, and the C# xUnit pins the defaults against numbers hand-written in the TEST (that arrangement locked an off-spec groove once — repaired, see the guard's header). Measured 2026-09-09 (`00_07` HW.45): **14 such fields**, all in the assembly-level manifests (`anchor_assembly*.json`, `anchor_axial_stack.json`), and the sharpest are the ones that CROSS machine halves — `o_ring_gap_mm = 1.424f` is *derived* from in-silico script 52 (`ORING_CS 1.78 × 0.80`, and that window itself reconciles a `02_02 §3.2`/`§3.5` drift), `rf_clearance_min_mm = 12f` mirrors [`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md), and `zone1_insertion_mm = 30` carries **no provenance comment at all** while the same 30 lives in scripts 54/58 and in a JSON `_note` sentence. 🔴 **«All correct today» stood here until 2026-09-11 and it was FALSE for the very field this entry uses as its example — `rf_clearance_min_mm = 12f`.** [`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md), the home it names, requires **«≥ 8 мм (мінімум), бажано 10–15»** with «λ/40 = 8.6» as the ground and «HFSS обовʼязкова якщо < 10» as the trigger; the only `12` there is the OUTCOME of a proposed two-deck layout («standoff 8–10 над Power Deck, що стоїть ~2 над фланцем → ~12 ✓»). So the constant mirrors a design POINT as if it were a floor, and `52_z_stack_tolerance.RF_ANT_TI_CLEARANCE_MIN = 12.0` mirrors it again in the other machine half. 🔑 **Why the check passed anyway, and this is the portable half: the verification was of the ADDRESS, not of the CLAUSE.** «§5.3 exists and is about antenna↔Ti clearance» is true; «§5.3 requires 12» was never read. ⊕ `git log -S` prices it: the canon row was born 2026-05-16 (`4228f53a`), the 12 a month later in **two commits of one day** (`02469300` code · `52eb1f8a` docs), and it now stands in nine homes — one date, ONE witness, and contradicting its own source from birth. ⚠️ The in-silico half already had the rule that catches this and it was never applied here: skill `in-silico` #9 — **if canon gives a RANGE, say which END you took and why.** The 12 took neither end. **Practice: a record default that can be the EFFECTIVE value names its home in the comment beside it (canon row · CEM field · the in-silico script that computes it) — and «names its home» means you OPENED the home and read the clause, not that the address resolves; changing a number in one machine half, ask which artefact in the OTHER half re-states it, because the two share no identifier vocabulary and grep across them only works on the VALUE.**

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
   0.5*wallParam` ⇒ solid; a clean wall needs `wallParam ≪ amplitude`. 🔴 **That is the SHEET
   reading and it does NOT generalise — network treats the same number as a LEVEL (`eq < 0.5(w−1)`),
   where ≪-the-amplitude is not the rule and 0 / negative are ordinary.** **Porosity is
   voxel-dependent → MEASURE it** (a coarse voxel under-resolves voids → falsely high
   porosity; at 0.1mm the Ø11 anode reads 67.6% ≈ the 65% target, vs 21–28% at 0.4–0.5mm — that 67.6 is
   the SHEET branch at wallParam 1.0; the shipped network SKUs read 64.7–65.0 at 0.10).
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
   walls into **false** solid "islands" (measured 24–61% disconnected at 0.3mm → ≤0.3% at period/16) —
   🔴 **but the island FRACTION converges before the island COUNT and the labyrinth count** (2026-09-10,
   all seven shipped SKUs): at period/16 all five period-graded species SKUs (broadleaf · mangrove ·
   oak · pine · tropical) still read ONE pore labyrinth with 52–473 false islands, period/20 still
   fails broadleaf + mangrove, **period/24 is where all seven converge** (2 labyrinths for the six
   sheet SKUs, 1 for `stepped` at every step; `graded_porosity`, constant period, converges earlier). A volume-fraction
   reading certified «~0%» while the topology was still wrong — judge convergence by the COUNT, and
   treat «wall ≈ period/10» as an UPPER bound on a graded SDF. Pore-phase metrics (open/percolation)
   are fine at any step → `SampleAnchor` ties the step to the finest period/24. And a **sheet** gyroid is tricontinuous → `PoreClusterCount`==2 is a topology FACT,
   not a defect (don't gate on it).
   🔴 **That whole measurement is now HISTORICAL, and the way it expired is worth more than the numbers:
   applying the network verdict (2026-09-11) EMPTIED this rule's carrier without touching the rule.** The
   shipped set used to be six sheet SKUs, whose thin wall a coarse grid shreds — that is what welded two
   labyrinths into one and made `/24 → /16` red five rows. A network gyroid has ONE labyrinth by
   construction, so under-resolution has nothing to weld: re-measured the same day, the identical mutation
   leaves the whole shipped Theory GREEN. The rule still holds for a graded sheet wall; only its witness
   was gone, and nothing would have told you. Carrier restored as a dedicated pin that holds the real pine
   geometry at `sheet` on purpose (`AnchorTests.A_Graded_Sheet_Wall_Still_Needs_The_Period_24_Step`).
   🔑 **Reflex, general: after a change that narrows what the shipped set CONTAINS, re-run the mutations of
   the pins that ranged over it — a pin can keep passing because its subject left, and that reads exactly
   like a pin that still works.** NB `Ex_ImplicitGyroidGenus` is **misleading** (renders a gyroid on
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
11. ✅ **FIXED 2026-08-28 (HW.1) — the four symptoms below are CLOSED in `Drawing.cs`; the CLASS and its
    reflex stay, because the next null-defaulted field will read exactly as innocent as these did.**
    What landed: a single `Drawing.NotSpecified` marker replaces every `??`-default (title block,
    `NotesLines`, `CAD_REV`); the notes field-set is FIXED, so an absent field prints
    `Post-process: NOT SPECIFIED IN CEM` instead of removing its own line; a one-sided tolerance prints
    each side separately (the `?? 0` that rendered `bore: 0.1/0 mm` — a zero minus-limit, i.e. the
    TIGHTEST possible, invented — is gone); a NAMED feature with no limits still renders (this is what
    made `cathode_flange.json:shank_dia` reappear); the Ti-coin canvas 560 → 620 so the title block's
    last row is inside the viewport; and title-block cells cut at a measured budget **and say
    `… → NOTES`** — the flange's silent 22-char truncation and the coin's silent overflow were the same
    defect in opposite directions. ⊕ `DxfSafe` was measured against every `cem/*.json`: it mapped 7 of
    ~35 non-ASCII glyphs, so `§` · `—` · `→` · `×` · `−` · `↔` · `⇒` · `≪` · `α` · `β` · `₂` were added.
    ⚠️ Cyrillic stays escaped as `\U+XXXX` **deliberately** — that is standard DXF Unicode encoding,
    not corruption, and transliterating a part name would lose meaning for cosmetics.
    🔑 **The pin that closes the whole class is the ROUND-TRIP one** (`Shipped_Cem_Notes_Reach_The_Dxf_Verbatim`):
    it reads the REAL `cem/ti_coin*.json` and asserts every non-empty note reaches the DXF through
    `DxfSafe`. Every other test here feeds an INLINE literal, which is precisely why a drop and an
    invention coexisted for weeks under a green suite — and mutation confirms it: narrowing `DxfSafe`
    by one glyph reds that test alone. **When you add a `draw` kind, add its round-trip row too.**
    ✅ CLOSED 2026-09-11 for `topology` (below) — but note HOW, because the obvious fix was the worse
    one: the default was NOT flipped to `network`. Flipping it would have silently re-pointed four
    synthetic in-test coupons at a different branch while their comments still argued sheet wall
    thickness — one silent default swapped for another. Instead every shipped manifest now DECLARES its
    topology, pinned by `AnchorTests.Every_Shipped_Anchor_Cem_Declares_Its_Topology` (it reads the RAW
    json, because a parsed record cannot tell an absent key from an explicit `"sheet"`), so the default
    is load-bearing for no real part and a new SKU that omits the key reds instead of inheriting.
    🔑 **Generalises: when a default is wrong, ask whether to change it or to make it NON-LOAD-BEARING —
    the second is what removes the class, the first only moves it.**

    🔴 **A FIFTH member found and closed 2026-09-09 (HW.1): the SSOT line printed `cem.Name`, not the
    real filename.** `mechanical_lock.zone1.json`'s `name` field ("mechanical_lock_zone1") already didn't
    equal its filename stem, and that one call site was fixed by threading the caller's real `strFile`
    through — but `ti_coin.<alloy>.json` has the SAME mismatch (`name: "ti_coin_7nb"` vs the real
    `ti_coin.7nb.json`) and nobody had generalized the fix. **6 of 7 shipped `ti_coin.*.json` were
    printing a factory drawing whose own SSOT pointer resolves to a file that does not exist** — only
    the base `ti_coin.json` coincidentally matched, which is exactly why it went unnoticed this long.
    Worse: the existing test suite didn't just miss this, it *pinned* the bug (`cem.Name` manually set,
    asserted the underscore form printed). Fixed the same way the class prescribes: the round-trip pin
    now also asserts the real dotted filename appears in the SSOT line for the whole `ti_coin.*` family,
    not a new test file. **When threading a manifest through a new `draw` kind, grep for `cem.Name` in
    the SSOT-line context specifically — `Name == filename stem` is a per-CEM coincidence, never a
    guarantee.**

    <details><summary>The original diagnosis (kept — it is what the reflex is calibrated on)</summary>

    🔴 **The drawing tract SILENTLY invents and silently drops — and the reviewer sees LESS than the
    factory** (deep-dig 2026-07-16; the `topology: "sheet"` default below is ONE MEMBER of this class,
    not a one-off).
    - **Silent drop:** `Drawing.NotesLines` → `void Add(label, v) { if (!string.IsNullOrWhiteSpace(v)) … }`
      — a null CEM field removes the whole line. There is no empty `Post-process: ___` for the shop to
      query; the drawing looks COMPLETE. Same for `ToleranceLines`: `Feature` renders only if Plus **or**
      Minus exists (`cathode_flange.json`'s `shank_dia` was absent from BOTH svg and dxf **at the time of this diagnosis** — the 2026-08-28 fix that dropped fabrication from the drawing put it back in both), and
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
    </details>

    🔑 **Reflex when touching `Drawing.cs`/CEM (unchanged by the fix — it is what PREVENTS the next one):**
    ask "what does a NULL here print on a factory drawing?" — and prefer a loud `NOT SPECIFIED IN CEM`
    over a plausible default. ⊕ Second half, bought by the same pass: **a drawing has TWO readers with
    different eyes** (human SVG ⊥ machine DXF), so any change to notes/title-block must be checked in
    BOTH — every symptom above was invisible in one of them.
12. **`TopologyCrossChecks.cs` (ARCH.25 third phase, 2026-09-09) — Euler-χ / tortuosity / as-printed
    cross-checks, wired into `verify` as `[nice-to-have]` INFORMATIONAL lines, not the `VERIFY OK/FAILED`
    gate.** Two real bugs only surfaced on the actual shipped geometry, not on synthetic unit-test inputs —
    worth the reflex generalizing beyond this file: a toy-scale test proves the ALGORITHM compiles and
    handles its edge cases, never that it survives REAL geometry at true scale. (a) The visited-marking in
    the tortuosity walk flagged every *offered* neighbour as visited, not just the one stepped to — passed
    every unit test, then converged 0/100 on the real 88×88×320 pine grid (trapped by its own over-marking).
    (b) The walk's original bias treated lateral wandering as equal to real progress, so it burned its
    self-avoidance budget circling in one plane — invisible on small synthetic clusters, fatal on the real
    anchor's actual pore network. Both were only caught by running `dotnet run -- verify` against a real
    shipped `cem/*.json`, never by the xUnit suite alone. **On the shipped seven (2026-09-10, intent step
    period/24):** Euler-χ sound on all; tortuosity mean ≈1.3–1.4; the as-printed check is a morphological
    OPENING of the solid at the SLM floor (ball radius floor/2; ⚖️ 2026-09-10, applied 09-11, that floor
    is a per-CEM **vendor input** `slm_min_wall_mm` — absent ⇒ the canon 200 µm default, and `verify`
    prints WHICH of the two it used. 🔴 The floor also sets the measurement grid, `min(adaptive, floor/4)`,
    so a vendor floor of 0.1 instead of 0.2 is ~8× the cells and about an order of magnitude more time —
    a cheaper machine is not a cheaper run), and its sub-floor
    share is monotone in the rim wall — `stepped` 71.8 % · `broadleaf` 49.7 % · `pine` 24.4 % ·
    `mangrove` 20.5 % · `oak` 4.3 % · `tropical` 1.5 % (`graded_porosity` 12.5 %). ✅ **Those six are the
    SHEET era. Re-measured 2026-09-11 after the network verdict landed, same grid and floor: `broadleaf`
    1.3 % · `pine` 0.7 % · `mangrove` 0.7 % · `graded_porosity` 0.4 % · `oak` 0.3 % · `tropical` 0.2 %,
    `printed solid-disc` 0.0 % on all six, and no SKU reads ⚠ DIVERGES any more** — the metal the floor
    was deleting WAS the sheet wall. `stepped` is untouched at 71.8 % (third branch, outside the verdict).
    🔴 **Read `print_fidelity_matches` only WITH `print_fidelity_sub_floor_solid_fraction`:** the boolean
    compares topology CLASS — `stepped` reads ✓ while losing the most metal, and the sheet SKUs read ⚠
    because one pinhole merges their two labyrinths. 🔴 **The previous form of this check — a coarse RESAMPLE at
    floor/2 — measured the wrong thing in the wrong order:** on 5 of 7 SKUs its «print» grid was FINER than
    the intent grid, so «DIVERGES on pine» reported the intent grid's own under-resolution (period/16,
    gotcha #8) under a manufacturability caption, and on `broadleaf` the two grids coincided and it
    matched vacuously (`ssot-maintenance` §Guard-craft #78 — a pin on an identity transform); a resample
    AT the floor fragments every SKU (lattice aliasing of a curved wall). Reflex: a check named «X vs Y»
    must prove which grid is coarser BEFORE its ⚠ means anything — and a class-level boolean must ship
    beside the magnitude it is blind to. Design-justification + numbers → [`01_02 §6`](../../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); open decision → [`00_07` HW.33](../../../docs/00_07_Action_Plan_Tracker.md).

## Common Tasks

- **Add a part / per-species SKU**: write `cem/<name>.json` (with a `kind`) + a generator in
  `src/SilkenCad/` + wire the `build`/`verify` switch in `Program.cs`; `dotnet run -- verify`.
- **Change anchor geometry**: edit `cem/anchor_zone1.*.json` (Ø, bore, period, wallParam).
  Geometry numbers are owned in `01_01 §5` + founder decisions in `00_07 HW.33`; **MEASURE
  porosity after** (gotcha #4). Render via `Zone1Anode.Anode` (the ctor route, gotcha #1).
  ⚖️ **Topology = `network` (ratified 2026-09-10, APPLIED 2026-09-11)** — every shipped `anchor_zone1.*`
  but `stepped` now declares it; `stepped` is a separate, already-decided THIRD branch (`ZonedGyroid`).
  🔴 **The live rule is that `wallParam` NEVER carries across a topology flip, and it is not cosmetic:**
  the param is a BAND on sheet (`|eq| < 0.5·w`) and a LEVEL on network (`eq < 0.5·(w−1)`), so the
  sheet-era 1.0 lands network at 50.2 % porous / ~27 GPa — *stiffer* than the branch it replaced. Re-solve
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
- **Monolithic bus rod (`01_01 §1.4`, HW.34, SHIPPED)**: `bus_rod_diameter_mm` > 0 ⇒ a SOLID central
  rod core. `Zone1Anode.BuildMonolithic` = `Anode` (gyroid, ctor) **+ `BoolAdd(BusRod.voxConstruct())`**
  (solid via voxConstruct, gotcha #9 — NOT the SDF ctor). 🔑 **Porosity stays a property of the gyroid**
  (`Anode` + the annulus envelope, `InnerRadiusMm` = rod surface) — the rod is SDF-invisible, so connectivity
  /porosity gates are untouched; `verify` separately MEASURES the fused rod volume (`ReportAnchor`, ≳π(r)²·L).
  Cathode keeps its channel (`mechanical_lock.zone3`/flange bore); anode shank `bore→0` (solid). F3 audit =
  `AxialStack.BusRodClears` (rod + 2·liner ≤ channel).
- **Graded gyroid (v2, SHIPPED)**: own SDF, **NOT** LEAP `ImplicitModular` (`FunctionalScaleTrafo`
  is a hard-coded Z-demo, not radial; LatticeLibrary upstream is DORMANT — our pin IS `HEAD main`, so
  re-check it by `git ls-remote`, never by age; the one that IS behind is `LEAP71_ShapeKernel` — skill
  `dependency-update`). Three CEM-driven axes
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
  **pore** OK at the coarse step, **solid** needs ~period/24 (gotcha #8 — the labyrinth COUNT converges
  later than the island FRACTION). The `verify` gate adds
  open≥95% · solid-disc≤2% · percolate axial+radial. Topology-agnostic by construction — which is why it
  survived the sheet→network switch unchanged (the HW.33 axis it once fed is closed).
- **Capsule-end assembly (`Assembly.cs`, SHIPPED)**: brings Деталь 3 ↔ Деталь 4 into one frame at the
  bayonet datum (radome lock-groove ↔ flange lugs) via `MeshUtility.voxApplyTransformation` (lift; the
  per-part `Build`s stay untouched) and MEASURES the residual mismatch (radial / bayonet-Z / RF) + models
  the skirt/inboard MATE-Ø candidates. An AUDIT table — `verify` exits on a broken render only; the
  mismatch numbers are asserted by pure xUnit. Canon `02_02 §4.4`. ⚖️ **The reconcile is NOT one bench job:
  the RADIAL half was ratified 2026-09-10** (Ø25 stays, a local internal rim boss carries socket + seal land,
  `skirt` withdrawn because it deletes the sealing face), **and the bayonet-Z half is an open ⚖️, not bench
  work** — because the mismatch is `t/2 + lockGrooveZ + gap`, three positive terms, so no assignment of the
  frozen dims reaches zero and the lug needs a Z of its own (`Assembly.RequiredLugZMm`). ⊕ The two "separate"
  equations share `Rf + mismatch = cavityH + gap`: lowering `lockGrooveZ` pays into BOTH, `cavityH` into RF
  alone. Open in `00_07` HW.33; HW.8.8 is the bench leg that follows it, not the decider.
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
  `cathode_flange` (Phase 2, rode the Ø25 freeze) + `mechanical_lock`** (HW.26, 2026-09-09 — one
  generator/CEM `kind` shared by `mechanical_lock.zone1.json` and `mechanical_lock.zone3.json`, SIDE view cuts a real DIN-471
  groove at the CEM's own z-offset), all three with the mirror xUnit set incl. the shipped-CEM
  round-trip (⛔ test COUNTS are not quoted anywhere — the roster is `DrawingTests.cs`).
  Still deferred: Zone-2 sleeve, radome, **`draw anchor_zone1`** (gyroid inspection-card — does NOT exist,
  so the Zone-1 coating-restriction map has no carrier yet), assemblies. NORM (why a drawing is derived
  from the CEM, what it must carry, the loud-absence rule) = canon [`01_02 §6`](../../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md);
  research + phase roster = `tools/cad/docs/drawings_program.md`.
  🔴 **`docs/images/cad/*.drawing.svg` is a SECOND artefact and nothing re-runs the gallery for you.** It
  is committed and opens straight from GitHub (a blob-rendered SVG) — i.e. the drawing outsiders see —
  and it sat on the pre-2026-08-28 output for weeks after that fix landed in code, publishing exactly the
  dropped/invented lines the fix removed. ⚠️ **`wiki:sync` does NOT carry it, and writing that it does was
  a FABRICATED mechanism** (measured 2026-09-09): `lib/tasks/wiki.rake` syncs only the canon `NN_NN_*.md`
  and copies an image only where a doc EMBEDS it as `![…](…)`; no canon doc embeds these, so that set is
  empty. Want them on the wiki — embed them in a canon doc first. Change `Drawing.cs` or a CEM ⇒ re-run
  `tools/cad/scripts/render_gallery.sh` (or at least its DRAWING loops — ⛔ "its two `draw` lines" stood
  here and was wrong by half: the script now has TWO loops covering FOUR targets, `ti_coin` ·
  `cathode_flange` · `mechanical_lock.zone1` · `mechanical_lock.zone3`, so obeying the old wording left
  both lock sheets stale — the exact lag this gotcha exists to stop. Read the loops, never a count) and commit the SVGs. A pin now reds on the CONTENT drifting apart
  (`Published_Gallery_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame`) — ⛔ but its declared
  ceiling is content + frame-fit, NOT byte-currency, and the PNG renders beside it are pinned by nothing.
- **Render / section for presentation (`render`/`section`, SHIPPED)**: `render <cem>` = a PicoGK native-viewer
  screenshot (gold Ti-metallic material); `section <cem>` = a −X cutaway (shows the bus rod through a dense gyroid
  where `ColorFloat` alpha can't). Display-gated (gotcha #10); output → `out/*.png` (native TGA → `sips`). The
  presentation gallery `docs/images/cad/` is NOT SSOT (`tools/cad/scripts/render_gallery.sh` rebuilds it)
  — ⚠️ but see the drawing bullet above: **not-SSOT is not a licence to lag**, and the PNGs there have no
  pin at all, so a stale render is invisible to everything.
- **Local-verify** (`export PATH="$HOME/.dotnet:$PATH"` first — the SDK is NOT on PATH, and «dotnet is not installed here» has already been asserted falsely once, 2026-09-10): `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1) → `dotnet run -- draw cem/<x>.json` (SVG+DXF → out/)
  → `dotnet test`. CI = enterprise 2-job `cad_smoke.yml` (logic = Linux pure-xUnit hard [incl. draw/DXF]
  + render = macOS build-hard + verify best-effort, Library.Go 139 headless).
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink (vendored LEAP source, kept out of owned code).
