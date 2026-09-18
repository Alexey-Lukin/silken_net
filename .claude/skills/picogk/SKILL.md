---
name: picogk
description: "Use when working on the silken_net Code-as-CAD surface — PicoGK voxel/SDF geometry generation in tools/cad/ (the Ti-coin in-vitro coupon, the Zone-1 gyroid anode, the CartesianGyroid SDF, the PEEK Radome — shipped, `dotnet run -- build cem/radome.json`) and the CEM (Computational Engineering Model) manifests that drive them. Knows the non-obvious gotchas — render lattices via `new Voxels(IImplicit, BBox3)` + BoolIntersect NOT voxBounding.voxIntersectImplicit (uncatchable native OpenVDB abort at fine voxel on thin bored parts), headless `Library.Go(voxel, task, bEndAppWithTask:true)` not the stale v1.6 `new Library()`, ImplicitRadialGyroid axis-singularity → cartesian gyroid, dimensionless gyroid wallParam + voxel-dependent porosity (MEASURE it), the voxel-resolution floor, ImplicitUsings-ENABLED for vendored LEAP source — the voxel-FE elasticity tract (`fea` → apparent stiffness of the real part in units of E_solid; **`fea --fit` → the Gibson-Ashby `C`/`n` MEASURED over a wall_param sweep since 2026-09-12**, per-resolution caches under `tools/cad/cache/fea/` pinned to canon by `scripts/fea_canon_sync.rb`; the formula is never our stiffness CALCULATOR, but its coefficients are now our MEASUREMENT — and a single-density `C` is a statement about the GRID, never about the lattice), the resolution-adequacy gate (is a declared feature ≥2 voxels on the grid its own manifest asks for), and the local-verify discipline (`dotnet run -- verify` → metrics.json, exit 0/1). ALSO the engineering-drawing tract: `draw <cem>` → SVG (human) + DXF (factory, GD&T/CMM acceptance) built from the CEM `tolerances`/`notes` blocks, the rule that an absent field prints `NOT SPECIFIED IN CEM` rather than a plausible default, the two readers (SVG clips, DXF does not), and the committed gallery under docs/images/cad that lags its generator unless you re-run it. Routes to 01_02 §6 (PicoGK stack + Noyron methodology + the drawing NORM) + 01_01 §5 (anchor geometry) + tools/cad/README, does not restate. Examples: \"generate the gyroid anchor\", \"add a CEM part / per-species SKU\", \"change anchor Ø / porosity / pore period\", \"why does the anchor crash with 'outside value 0'\", \"add the radial pore gradient\", \"build the Ti-coin STL\", \"make a factory drawing / DXF\", \"add a surface-finish or coating note to a CEM\", \"what is the anchor lattice stiffness / run the FEA\", \"is this feature resolvable at this voxel\", \"set up the .NET CAD project\"."
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
| `docs/00_07_Action_Plan_Tracker.md` HW.1 / **HW.33** | Build state + the anchor geometry audit (founder decisions: orientation-agnostic gyroid (б), Ø11; the June gaps are spent — PEEK/hole chain frozen, FEA-E measured — so the open set is its `**Стан:**`, split still-judged ⊥ ratified-but-unapplied) |
| `docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md §6` | Cross-biome 5-SKU (pine/oak/broadleaf/mangrove/tropical) |
| `docs/00_03_TRL_Matrix_HIL_and_Beyond.md §3.6` | Code-as-CAD vs generative-AI; In-Silico for the Hardware stream |
| `tools/cad/docs/drawings_program.md` | Engineering-drawing program: CEM-native DXF (netDxf) + SVG, the ASME-Y14.5≠projection fix, lattice-as-inspection-card, phased §7 rollout |
| `extern/.../README_ImplicitLibrary.md` | LEAP's own implicit/TPMS guide (splitting logic, modular workflow for the graded v2) |

## Source Files

| File | Role |
|------|------|
| `tools/cad/cem/*.json` | CEM manifests — the Git-SSOT parameter inputs (`kind` discriminator: `ti_coin`, `anchor_zone1`, `mechanical_lock`, `cathode_flange`, `radome`, `zone2_sleeve`, `anchor_assembly`, `anchor_axial_stack`) |
| `tools/cad/src/SilkenCad/Program.cs` | CLI dispatch — ⛔ ростер бери з `switch` у `Main`, не звідси (він уже раз відстав на три верби): станом на 2026-09-12 це `smoke`/`build`/`verify`/`sweep`/`scan`/`draw`/`render`/`section`/`probe`/`fea` + `RunHeadless` (the `Library.Go` wrapper); `draw` is pure-managed (no Library.Go), `render`/`section` drive the native viewer |
| `tools/cad/src/SilkenCad/Cem.cs` | CEM records + JSON parse (snake_case). Engineering-drawing PMI lives here: optional `ToleranceSpec` (fits / Lamé-µm / GD&T datums / a LIST of `Features`, since 2026-09-11 — the single slot it replaced silently capped a part at ONE toleranced size, which is why the cathode flange could not give its own primary datum a dimensional row; a named feature with NO limits still renders, as loud absence) + `NotesSpec` (material/process/**post-process**/surface/coating-restriction/lattice-spec/inspection) on each part record — Noyron-native SSOT, fed to `draw` |
| `tools/cad/src/SilkenCad/Drawing.cs` | CEM-native engineering drawings (`draw <cem>`): **SVG (human) + DXF via netDxf (CAD-native factory deliverable, opens in AutoCAD/Fusion)** — no PDF (never built; `drawings_program §3`). Pure-managed string/entity build, no Library.Go. Consumes the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text); `DrawingStandard` param (ISO 1st-angle default / ASME). ⛔ **The roster of shipped kinds is `Program.Draw`'s `switch`, never a prose list here** — this line carried one and it was stale within the day. What does NOT rot: each kind is a `Drawing.X` + `Drawing.XDxf` pair, and adding one means adding its shipped-CEM round-trip row (gotcha #11) and its gallery pin. Phasing + the kinds deliberately NOT drawn, with their grounds → `tools/cad/docs/drawings_program.md §7`. ⚠️ gotcha #11 |
| `tools/cad/src/SilkenCad/TiCoin.cs` | Ti-coin coupon — `BaseCylinder` disc + `BaseRing` eyelet, `BoolAdd` |
| `tools/cad/src/SilkenCad/Zone1Anode.cs` | Zone-1 anode + `CartesianGyroid:IImplicit` (the from-scratch SDF) + `Anode()` render path |
| `tools/cad/src/SilkenCad/Validation.cs` | golden-metrics via `Voxels.CalculateProperties` (porosity needs an envelope ref) + reuses LEAP `Measure.fGetSurfaceArea` |
| `tools/cad/src/SilkenCad/Connectivity.cs` | ARCH.25 two-phase topological audit — SDF-sample + 6-conn flood-fill (open/closed-pore, percolation, solid-island, specific-surface); pure-managed, display-less xUnit. ⊕ Since 2026-09-12 it is also the MESH SOURCE for `VoxelFea`: `SampleRegion` (sampling with a phase OVERRIDE — the SDF-invisible bus rod has to be FORCED solid) and `LargestComponentMask` (membership, which `Components` does not keep) |
| `tools/cad/src/SilkenCad/VoxelFea.cs` | **Voxel-FE пружності** (00_07 HW.51/HW.33) — solid-воксель `Connectivity.Grid` → трилінійний гексаедр; матрично-вільний поелементний множник, 8-кольоровий за парністю вокселя, Якобі-CG. Верб `fea`. ⛔ Меш бере лише найбільше гране-звʼязне тіло (плавучий острівець = жорсткий рух), відкинуте — рапортується. Стеля оголошена в шапці класу; числа — `01_01 §5.2`, кеш `tools/cad/cache/fea/` (ВЕРСІОНОВАНИЙ, на відміну від `out/`) |
| `tools/cad/src/SilkenCad/Resolution.cs` | **Достатність роздільності** (00_07 HW.51) — чи влазить фіча у воксель, якого просить її збірка. Ходить по РОЗПАРСЕНОМУ дереву записів, не по ключах json, і несе ВИВЕДЕНІ величини (щілина стрижень↔канал, товщина ґратки). HARD-носій — `ResolutionTests` + рядок у кожному `verify`-репортері |
| `tools/cad/src/SilkenCad/MechanicalLock.cs` | §4.3 mechanical lock — `MechanicalLockShank` asymmetric ratchet-barb + DIN-471 groove SDF on the shank (Zone-1 solid monolithic / Zone-3 channelled); render = solid `voxConstruct` + thin barb-ridge `BoolAdd`; self-support metric (Noyron manufacturing-awareness) |
| `tools/cad/src/SilkenCad/CathodeFlange.cs` | Деталь 3 — Zone-3 cathode flange (Ø25): reuses the §4.3 shank/barbs via `ShankCem` + radial bayonet lugs + bus channel + the capsule's SINGLE face-seal O-ring groove on the top face — depth · width · radii DERIVED from the `o_ring` block and the socket band shared with the radome (`CathodeFlange.ORingGroove*`; 00_07 HW.33 branch (а), applied 2026-09-14), nothing stored; the flange sheet draws it as geometry in both readers and its depth tolerance as loud absence |
| `tools/cad/src/SilkenCad/Radome.cs` | Деталь 4 — PEEK radome v2c (Ø25): hollow dome + shield bell + a LOCAL INTERNAL RIM BOSS (`Radome.Boss*`/`SealLand*`: socket band `lug + clearance` outside ⊥ seal land `gland width + 2·clearance` inside; rim cavity ≤ Ø15.57 at the 80 % gland fill — every term a MINIMUM, a ceiling HW.9 takes as an input, ⚖️ 2026-09-14) + the bayonet socket, cut in the boss's OUTER band only + PCB cavity; the rim is FLAT — the single O-ring groove is the flange's, derived from the `o_ring` block both manifests carry (gotcha #9 INVERTED — hollow is intended). ⛔ **ONE ratified-but-still-shipped divergence lives in this file:** the CAP is still a FULL HEMISPHERE where ⚖️ 2026-09-11 ratified a FLAT CROWN with an R5 edge fillet (rise 12.5 → 5.0, height over bark 25.5 → 18.0), and it waits on ⚖️ HW.30 (piezo placement), not on a budget. ⚠️ Applying it silently inflates `hollow_fraction`, because `Validation`'s reference solid still adds a hemisphere — recompute that formula in the same commit — and `bell_rise_mm`/`bell_radius_mm` must become DRIVERS, which today they are not. ⚠️ The raised COLLAR that carries the lugs at `Assembly.RequiredLugZMm` (20.5) is modelled on NEITHER part — its wall is set by nothing (no bayonet load model), and a placeholder would print on the flange sheet as a decision — so the socket keeps its L-slot shape (clipped to the outer band, pocket `socket band − skin` = 1.6 deep, skin 0.2) until that leg reshapes it: socket and collar are the female and male halves of one band. `verify radome` MEASURES the seal land solid over the full rim face (`SealLandSolidFraction`), the xUnit pins only derive it |
| `tools/cad/src/SilkenCad/Assembly.cs` | Capsule-end mate-audit (Деталь 3↔4, `02_02 §4.4`) — bayonet datum via `voxApplyTransformation` lift + Z/MATE-Ø/RF mismatch + skirt/inboard candidates; pure mate-math (xUnit) + render interference (`verify`) |
| `tools/cad/src/SilkenCad/Zone2Sleeve.cs` | Деталь 2 — Zone-2 PEEK sleeve (bore Ø11 / OD Ø15 / 50 mm): plain hollow tube via `BasePipe` (smooth bore; hex + flange-shoulder deferred, bench-gated) |
| `tools/cad/src/SilkenCad/AxialStack.cs` | Full axial stack mate-audit (Зони 1↔2↔3↔4, `02_02 §4.5`) — press-fit interference + insertion budget + span; reuses `Assembly.Build` + Zone-1 envelope; pure mate-math (xUnit) + render (`verify`) |
| `tools/cad/src/SilkenCad.Leap/` | vendored LEAP source compiled in (ImplicitUsings ON, warnings relaxed — not ours) |
| `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` | git submodules (source-only; not on NuGet) |

> Voxel/triangle counts, porosity AND the FE stiffness ratio all drift with voxel size — don't hardcode them ([[feedback_no_volatile_counts]]); MEASURE via `verify` (geometry) or `fea --sweep` / `fea --fit` (stiffness AND the Gibson-Ashby coefficients — a single row is an UPPER bound by construction, and the FITTED `C` itself still moves with the step (0.954 · 0.989 · 0.983 at period/16 · /24 · /32), so nothing is quoted without its convergence ladder).

**State** (what is built / open ⚖️ / curator lessons) lives in memory, not here: `[[project_picogk_code_as_cad]]` (⊕ its journal twin `[[log_picogk_cad]]` — the BODIES were evicted there 2026-09-12, so a pin followed from the parent alone lands on a rule without its numbers) · `[[project_bus_monolithic_onehome]]` (bus topology + the PEEK-liner trap below) · `[[project_coin_bakeoff_trl4]]` (the Ti-coin keystone this CAD feeds). This pointer was **missing** until 2026-08-08 — every sibling skill (`ssot-maintenance`, `ml-engineering`, `web3-pipeline`) carried one and this file did not, so CAD state was reachable only by someone who already knew it existed.

## Gotchas Not Obvious From Docs

0. 🔴 **`tools/cad/cem/*.json` is the parameter SSOT, and its `liner 0.15 mm` is now a RATIFIED branch — but read why before you touch it.** For months that number silently elected PEEK while [`01_01 §1.4`](../../../docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md) still called the implementation open: Parylene ~10 µm and TiO₂ ~0.1–10 µm cannot reach 0.15 mm, so a frozen dimension had decided an undecided question. ⚖️ **Closed 2026-09-10 in PEEK's favour — the liner is STRUCTURAL — and its STRUCTURAL half was RE-OPENED 2026-09-10** (`00_07` HW.34). The ground was «without lateral support not one of the six bake-off alloys reaches infinite fatigue life at the canon rod Ø1.0», and that ground is an AS-PRINTED number: `55_bus_mechanical` derates endurance by `AS_PRINTED_DERATE`, so the rod-fabrication verdict of the next day (a welded cold-drawn wire) doubles every safety factor. 🔴 **Measured 2026-09-11 the doubling cleared only FOUR (Ta 1.41 · CP-Ti 1.96 under the SF-2 line) — and that reading was RETIRED 2026-09-12 with the span it rode:** at the CEM-derived 23 mm protrusion every alloy clears bare on the welded branch (SF 2.21–6.08, binding Ta 2.21), and the printed branch predicts no failure either (1.10–3.04). ⛔ **Both figures are era-0.45 and the model LEFT that point: since 2026-09-18 it runs at the ratified LOW end `σ_e/σ_y = 0.40`** (⚖️ founder 2026-09-17, `00_07` HW.34), where the free cantilever clears **5 of 6** — Ta **1.96** does NOT, and the printed branch turns Ta into a predicted failure (0.98) — while the shipped LINED configuration keeps its verdict at **SF 2.45**. So the live bare-rod numbers are **1.96–5.41** welded / **0.98–2.70** printed. Quote the configuration and the ratio end, never a bare «all six». ⛔ Do not quote «four of six» either — an era-36 figure. ⛔ The model is a homogeneous cantilever, so the ×2 describes the WIRE, not the JOINT — ⊕ but since 2026-09-12 the seam is BOUNDED rather than unpriced: its knockdown `k` is measured nowhere, so `55` inverts the question and reports the break-even `k` instead (binding candidate `Ta`) — ⛔ and the bound REVERSED on 2026-09-12 when the rod protrusion was corrected (break-even 0.554 against our own `AS_PRINTED_DERATE` = 0.50, −0.054), then was RETIRED outright on 2026-09-14: the stress it was inverted from is a free-cantilever root stress at a free-shape crossing station, which no equilibrium configuration produces, and the root sees two regimes (a bracketed coaxial drag ⊥ a static mean from a channel offset) that no single fully-reversed `k` can price without a mean-stress model the tree lacks (`55` §`weld_seam.break_even_k_not_derived_because`; the root loading per regime and geometry is what the cache carries instead). **So there is no house number bracketing the weld at all — `k` comes from the vendor.** ✅ **RE-JUDGED the same day (⚖️ founder 2026-09-11): the liner stays STRUCTURAL, and the whole fatigue ground was RETIRED rather than narrowed.** Both `L_FREE_*` columns are FREE cantilevers — no wall anywhere — while the rod threads a Ø1.35 bore, so at the ~165 µm play a 10 µm film leaves, the rod takes up the play and bears on the wall inside the bore. ✅ **That station was RE-DERIVED 2026-09-14 on the contact equilibrium** (`tools/in_silico/lib/beam_contact.py`, one solver for scripts `55` and `68`): the free-cantilever reading at full drag was never a station — on a coaxial channel the wall is met only at the EXIT (the liner's flush end) on every swept µ and every geometry, the mouth is never reached, and the root stress against a rigid wall (8.04 MPa on the placeholder, µ-invariant) is the LOWER end of a bracket to the Ti-bore stop (56.3 MPa at µ 0.5) — the contact compliance that places it is unmeasured — while a channel off the root axis by more than the play makes the mouth a contact station and puts a MEAN on the root. Every «bears N mm in / on the mouth edge on µ …» figure in this entry is a free-shape crossing and RETIRED; the ratified verdicts stand with their grounds corrected beside them (`01_01 §1.4`), the channel-coaxiality ⚖️ stays open (`00_07` HW.34). 🔴 **«on every µ the script sweeps» stood here and was falsified by the protrusion fix (2026-09-12), NOT by a new argument:** a 23 mm span is a stiffer rod, so a conformal film now first touches the wall at 13.9–23.0 mm, i.e. past the bore end at the lowest swept µ (0.2) only — it still bears on µ 0.3–0.5. ⚖️ The ratified verdict holds — the SHIPPED branch (PEEK liner) touches down on every µ (at the EXIT, per the equilibrium above; the «past the mouth / on the mouth edge» stations this line used to carry are retired) — but the argument against the REJECTED conformal branches is weaker than this line claimed: they touch down on part of the sweep («two lowest µ» and «no longer empty» came from a regime label that read «not on every µ» as «never», fixed in `55` 2026-09-14; since the equilibrium re-derivation the same day the per-branch answer is `clearance_regime.branches[].touches_down_on_mus` with an explicit quantifier — on the placeholder the films touch down at the exit on µ 0.3–0.5, across the lock window on every µ). For the shipped branch an unsupported SF is still a number for a configuration that does not exist. What carries instead is WEAR: the same contact makes rubbing geometrically forced, and a 10 µm film is being asked to be a bearing in a THROUGH bore of L/D ≈ 12.6 whose wear-through is a ~0.5 V anode↔cathode short (the ratio is DERIVED in the cache since 2026-09-11 — `clearance_regime.channel.aspect_ratio_l_over_d` — so it moves with the channel Ø instead of being retyped). 🔑 **Two portable halves.** (a) **Before quoting an idealised SF, ask what the idealisation ASSUMES AWAY** — here a wall the real part has; a free-cantilever number is not conservative when the omitted feature changes the regime rather than the magnitude. (b) The thermal sense here is **INVERTED** relative to the Zone1↔2 press-fit the corpus models: PEEK is the INNER part, so cooling shrinks it AWAY from the Ti wall (~2 µm diametral over 40 K), where in Zone1↔2 cooling grips harder. **The INSULATION half was never in dispute.** 🔑 **What survives as the lesson, and it is the reason this entry stays:** the contradiction lived in the CANON PROSE, and the manifest was the symptom — patching the JSON toward another branch would have broken the `AxialStack.BusRodClears` F3 gate (rod + 2×liner ≤ channel) instead of settling anything. ⚠️ **Both halves of the sentence that used to close this entry are now spent, and in opposite ways.** F3 was `≤` and blessed a ZERO-clearance stack — it is **`<`** since 2026-09-11, because the clearance verdict opened the channel to Ø1.35 and made zero a state nobody intends (pin: `Zero_Nominal_Clearance_Is_Not_A_Pass__The_Pre_Verdict_Channel`). And clearance ALLOCATION is no longer an open leg — direction and size are both ratified (`00_07` HW.34, branch (в)); what stays open is the ROD side (drawn-wire tolerance and `Sa`, in no canon) and the diametral BAND of the machined bore, which is an RFQ answer, not a computation. The gate still judges NOMINALS only.

0b. 🔴 **A manifest can be silent for a SECOND reason, and this one is worse than a default: the record has no SLOT, so the key you write EVAPORATES.** `Cem.Parse` runs without `UnmappedMemberHandling.Disallow`, so an unmapped member is dropped without a word — and until 2026-09-11 `AnchorCem` (every `anchor_zone1.*`) and `RadomeCem` had **no `Notes` property at all**. A `notes` block written into those manifests would have parsed cleanly, rendered nowhere, and read as done; the tracker leg that asked for it (`00_07` HW.1) described the gap as «the manifests do not carry notes», which is the symptom, not the mechanism. ⊕ The tell that this is a distinct shape from 0a: there a WRONG value is in force, here NO value exists and nothing says so. 🔑 **Reflex before writing any new CEM field: grep the record in `Cem.cs` for the property FIRST — a JSON key with no matching property is not a small mistake, it is an invisible one.** ⚠️ And the same absence hides in the opposite direction: `Drawing` renders a FIXED field set, so a field the record holds but the generator's kind never draws is equally mute. ⛔ Carriers, since neither is gated: the notes are pinned present by `AnchorTests.Every_Shipped_Anchor_Cem_Declares_Its_Coating_Restriction` — declared ceiling PRESENCE, never correctness. 🔴 **The carrier half CLOSED 2026-09-11 (`draw anchor_zone1` + `draw zone2_sleeve`), and closing it proved this gotcha catches a FIELD and not a CLASS: `AnchorCem` had no `Tolerances` property either**, so the very next block written into those manifests would have evaporated exactly the same way, one day after the `Notes` fix. The two holes sat in one record and the first pass saw only the one it was looking for. **So the reflex is not «grep the record for THIS property» but «list what the record holds against what the schema offers» — the absence you are not hunting is the one that survives.** `radome` stays deliberately undrawn (its cap is still the hemisphere the ratified flat crown rejects — ⚖️ HW.30, HW.33; the rim boss and flat rim ARE applied), so its notes are still a source without a carrier (`00_07` HW.1). ⊕ Worth carrying from the same pass: the production ORDER of `01_02 §1.3` used to read print+HIP → hot press-fit → EAAE → bake, which put the press-fit shank surfaces inside the PEEK joint BEFORE etching, so the dual-scale Sa/Sv spec did not reach them. ⚖️ **2026-09-17 INVERTED this: bake after the PEEK press-fit is FORBIDDEN** (measured — at 250 °C the Ø11 bore grows 180–217 µm more than the shaft), and since bake must follow the etch it degasses, BOTH surviving branches now etch the bare part and assemble afterwards — so those surfaces ARE etched, and the open question flips to whether an etched surface survives an interference fit (`00_07` HW.34/HW.26). A coating there is a FIT problem (2t of interference), not a DET one, on either branch.

0a. 🔴 **«CEM json = parameter SSOT» is true only where the manifest SPEAKS — and `cem_canon_sync` guards exactly that half, so the silent half has no gate at all.** Where a manifest omits a field, the effective geometry is the **`Cem.cs` record default**, and nothing binds that default to canon: the guard reads `cem/*.json`, and the C# xUnit pins the defaults against numbers hand-written in the TEST (that arrangement locked an off-spec groove once — repaired, see the guard's header). Measured 2026-09-09 (`00_07` HW.45): **14 such fields**, all in the assembly-level manifests (`anchor_assembly*.json`, `anchor_axial_stack.json`), and the sharpest are the ones that CROSS machine halves — `o_ring_gap_mm = 1.424f` WAS *derived* from in-silico script 52 (`ORING_CS 1.78 × 0.80` — the pre-verdict 20 % squeeze: ⚖️ 2026-09-10 ratified 24.5 % in ONE flange groove against a flat rim, APPLIED 2026-09-14 — the field is GONE, not zeroed, the squeeze is the flange groove's own derived depth (`CathodeFlangeCem.ORing`), and the gland spec now crosses the halves EXPLICITLY: both manifests carry the `o_ring` block, `52` reads it back and refuses a mismatch, `RadomeTests` pins the C# derivation against `52`'s cache), `rf_clearance_min_mm = 12f` mirrors [`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md), and `zone1_insertion_mm = 30` carries **no provenance comment at all** while the same 30 lives in scripts 54/58 and in a JSON `_note` sentence. 🔴 **«All correct today» stood here until 2026-09-11 and it was FALSE for the very field this entry uses as its example — `rf_clearance_min_mm = 12f`.** [`02_01 §5.3`](../../../docs/02_01_Hardware_Architecture_and_BOM.md), the home it names, requires **«≥ 8 мм (мінімум), бажано 10–15»** with «λ/40 = 8.6» as the ground and «HFSS обовʼязкова якщо < 10» as the trigger; the only `12` there is the OUTCOME of a proposed two-deck layout («standoff 8–10 над Power Deck, що стоїть ~2 над фланцем → ~12 ✓»). So the constant mirrors a design POINT as if it were a floor, and `52_z_stack_tolerance.RF_ANT_TI_CLEARANCE_MIN = 12.0` mirrors it again in the other machine half. 🔑 **Why the check passed anyway, and this is the portable half: the verification was of the ADDRESS, not of the CLAUSE.** «§5.3 exists and is about antenna↔Ti clearance» is true; «§5.3 requires 12» was never read. ⊕ `git log -S` prices it: the canon row was born 2026-05-16 (`4228f53a`), the 12 a month later in **two commits of one day** (`02469300` code · `52eb1f8a` docs), and it now stands in nine homes — one date, ONE witness, and contradicting its own source from birth. ⚠️ The in-silico half already had the rule that catches this and it was never applied here: skill `in-silico` #9 — **if canon gives a RANGE, say which END you took and why.** The 12 took neither end. **Practice: a record default that can be the EFFECTIVE value names its home in the comment beside it (canon row · CEM field · the in-silico script that computes it) — and «names its home» means you OPENED the home and read the clause, not that the address resolves; changing a number in one machine half, ask which artefact in the OTHER half re-states it, because the two share no identifier vocabulary and grep across them only works on the VALUE.**

1. **Render lattices via `new Voxels(IImplicit, BBox3)` + `BoolIntersect`** — NOT
   `voxBounding.voxIntersectImplicit(impl)`, which dies with an **uncatchable native abort**
   (`libc++abi … ValueError: expected grid A outside value > 0, got 0` — a process kill, not a
   .NET exception). ✅ **The WORKAROUND stands; its stated CAUSE was wrong and is now measured
   (2026-09-12, `dotnet run -- probe <voxel>`).** It is NOT «a thin bored part at fine voxel» —
   geometry is irrelevant. The convenience path passes the narrow-band width **in mm** into an
   **`int`** parameter, so below 1/3 mm `3 × voxel` truncates to 0 and the grid is born invalid.
   The boundary is therefore SHARP and ARITHMETIC, and the probe hits it exactly: **0.34 mm
   survives** (3×0.34 = 1.02 → int 1), **0.33 mm aborts** (0.99 → int 0, exit 134). So the
   «ceiling ~0.4 mm» this line used to carry is really **0.334 mm**, and it moves with nothing
   about our parts. ✅ **VERIFIED against the runtime source 2026-09-12 — the mechanism is no longer an inference:** `Source/PicoGKVdbVoxels.h` line ~390 does `Voxels oVox(oVoxelSize(), fBackgroundMM());` while that constructor's second parameter is `int nNarrowBand` (a VOXEL COUNT, `:68`) and `fBackgroundMM()` returns `m_roGrid->background()` in MILLIMETRES (`:755`). Two faults in one line — wrong unit AND a truncating type — and `VoxelSize ⇄ float` implicit conversion plus an `int`-only `fToMM` overload make the mix-up compile silently.
   ⛔ **DO NOT file this upstream: it is ALREADY reported and better than ours would have been** — [`leap71/PicoGKRuntime#26`](https://github.com/leap71/PicoGKRuntime/issues/26), opened **2026-06-27** by the PicoPie binding, same file, same line, same fix (`Voxels oVox(oVoxelSize(), m_nSdfNarrowBand);`). Still open and still live in 2.2.0 as of 2026-09-12, which is what our probe re-measured.
   🔴 **And that report names a SIBLING INSTANCE we had not found, which is SILENT where ours is loud — `voxProjectZSlice` is unsafe at OUR voxel sizes.** `ProjectZSliceDn`/`Up` use `m_roGrid->background()` (mm) as a SLICE COUNT, so below ~0.167 mm the loop body never runs, the end cap is never sealed and the projected solid is **non-watertight with no error at all** (their measurement: ~818 mm³ at 0.5 mm collapsing to ~22 mm³ at 0.1 mm). ⛔ **We do not call it today — verified by grep, the only mention in the tree is an obsolete wrapper in the vendored ShapeKernel — and we must not start:** every shipped manifest runs at 0.05 or 0.1 mm, i.e. deep inside its regime. A third and fourth candidate of the same family (imported grids hard-coding band 3, `vecToMM` truncating fractional voxel coords) are named there too; we use neither.
   🔑 **Portable, and it is why the probe verb is permanent: two independent parties reached the same line from opposite directions — a Python binding sweeping voxel sizes, and a C# project hitting one abort — and neither of us could see the OTHER instance.** A belief about someone else's kernel that nothing re-runs survives their next release; a belief about someone else's kernel that nothing SEARCHES survives their bug tracker. **Before writing an upstream report, search their issues — the answer may be there with more in it than you had.** ⊕ And when you do write one, hand over the PREDICTION, never the symptom: «0.34 survives / 0.33 aborts» they verify in a minute, «it crashes at fine voxel» sends them looking for a defect in YOUR geometry — which is exactly where we looked for months.
2. **`ImplicitRadialGyroid` is degenerate near r=0** (cylindrical singularity) — fine for
   large annular parts, empty grid for a small rod near its own axis. Use a **cartesian
   gyroid** (uniform everywhere, still bicontinuous → honors founder decision (б), HW.33).
3. **Headless = `Library.Go(voxel, task, bEndAppWithTask:true)`**, not `new Library()`
   (the v1.6 headless pattern → "relies on Library::Go" abort in v2.2). It briefly inits a
   Metal/GL viewer then closes with the task — so CI needs a display (macOS runner / xvfb).
4a. ⚖️ **«Porosity is voxel-dependent → MEASURE it» — the RULE stands, its suspected CAUSE was tested
    and REFUTED (2026-09-12, `00_07` HW.49).** Our fields return the gyroid EQUATION, dimensionless,
    where `IImplicit` is contractually millimetres and the runtime clamps at `3 × voxel` mm — measured,
    the active half-band is 0.83 voxels at period 2.5, 0.67 at 2.0, **0.43** on the `stepped` rim, against
    OpenVDB's «greater than one», and it does not scale with the voxel. That violation is REAL. The
    hypothesis built on it — that the 67.6 → 21–28 % collapse at coarse voxel is an artefact of the
    squeezed band, so first-order normalisation `d = f/|∇f|` would cure it — **is false on three axes**:
    at the working 0.1 mm the two agree within noise (64.9 ⊥ 64.7); at 0.4 mm normalisation is WORSE
    (42.4 vs 49.3); and on `stepped`, where the band is narrowest, the difference is exactly **zero**
    (66.4 ⊥ 66.4, surface 3.14 ⊥ 3.14). 🔑 **Why the violation does not reach the numbers:
    `CalculateProperties` rebuilds a level set from the MESH, and the mesh is extracted from the zero
    set, which the clamp does not move.** So the coarse-voxel collapse is honest under-resolution (a
    network ligament ≈ 0.36·period = 2 voxels at 0.4 mm), not a field defect. ⛔ Do NOT switch the
    shipped SKUs to `normalise_field` — the ⚖️ is recorded and the instrument (`NormalisedField`, off by
    default) stays only so the verdict can be re-measured if the KERNEL changes or an SKU appears with a
    period ≪ 1.3 mm, the two events its ground depends on.

4. **Gyroid `wallParam` is DIMENSIONLESS** (gyroid eq ∈ [-1.5, 1.5]), not mm: `|eq| <
   0.5*wallParam` ⇒ solid; a clean wall needs `wallParam ≪ amplitude`. 🔴 **That is the SHEET
   reading and it does NOT generalise — network treats the same number as a LEVEL (`eq < 0.5(w−1)`),
   where ≪-the-amplitude is not the rule and 0 / negative are ordinary.** **Porosity is
   voxel-dependent → MEASURE it** (a coarse voxel under-resolves voids → falsely LOW
   porosity; at 0.1mm the Ø11 anode reads 67.6% ≈ the 65% target, vs 21–28% at 0.4–0.5mm — that 67.6 is
   the SHEET branch at wallParam 1.0; the shipped network SKUs read 64.7–65.0 at 0.10).
5. **Voxel-resolution floor + gradient distortion** — sub-100µm pores need voxel ~0.03mm →
   ~10⁹-voxel grids. The Ø11 anode renders cleanly at 0.1mm (pores ~2.5mm); realistic 300→100µm
   pores are the HW.33 ceiling. 🔴 **The printability half of that ceiling is TOPOLOGY-dependent,
   and the `min pore ~1.2mm` this line carried is the SHEET number** (measured 2026-09-12,
   `tools/in_silico/scripts/66_gyroid_ligament_thickness.py`): at 65% a sheet WALL is 0.12·period (⚠️ since 2026-09-12 the two ratios are NAMED CONSTANTS — `TopologyCrossChecks.SheetThicknessPerPeriod` / `NetworkThicknessPerPeriod` + `LatticeThicknessMm(cem)`; the prose here is a FOURTH mirror of a canon value, so read the constant and edit `01_01 §5.5` first)
   but a network LIGAMENT is 0.36·period — 3× thicker — so at the 200µm SLM floor the minimum
   printable pore is ≈0.33mm on the shipped network branch, not 1.2mm. What survives: the
   PERIPHERY (100–150µm) is still un-printable on both machines; 500µm clears SLM and 300µm clears
   µ-LPBF. The pore TARGET is unchanged and stays bio-hub/FEA-gated — only its ground moved
   (`01_01 §5.5`). ⚠️ `stepped` is the one SKU still on the sheet formulation, so the 1.2mm figure
   is the live one for it. ⛔ Both instruments are isotropic and cannot see the minimum NECK of an
   inclined ligament, so the number errs optimistic by an unmeasured margin.
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
9b. 🔴 **A body can render PERFECTLY in its own grid and add NOTHING to the assembly — and its own
    volume is the metric that hides it** (measured 2026-09-12, `AxialStack` liner, `00_07` HW.34). The
    bus liner is a 0.15 mm wall at the stack's 0.2 mm voxel: `BasePipe.voxConstruct()` gives 9.99 mm³
    against 9.75 analytic, i.e. a healthy standalone body, while `voxMerged.BoolAdd(liner)` gains
    **0.00 mm³** — at that voxel the Ø1.0 rod and the Ø1.35 channel ARE the same voxels and the annulus
    between them has nowhere to land. ⛔ The first version of that audit reported the standalone volume
    and read as "the tube is there"; the tell that it was a MEASUREMENT SUBSTITUTION is that the merged
    volume was byte-identical with and without the tube while the triangle count moved. **Reflex: for
    anything added to a merge, measure the CONTRIBUTION (properties before ⊥ after the Bool), never the
    part's own volume — and when a feature is thinner than the voxel, say so where the geometry is READ,
    because a CEM-true dimension and a mesh that carries it are two different claims.**
    ✅ **Since 2026-09-12 the reflex has a MACHINE carrier and is no longer only a habit:** `Resolution.cs` + `ResolutionTests` red on any declared or derived feature under two voxels, and this very liner is on the exemption list BY NAME with its ground. The reflex still stands for the half a gate cannot reach — a feature that fits the grid and still fails to survive a Boolean.

9. **A FILLED (solid) body must come from ShapeKernel `voxConstruct`, NOT `new Voxels(IImplicit, BBox3)`
   — unless your field is CLOSED, and that exception is measured, not theoretical.**
   The symptom is real (`MechanicalLock.cs`: a Ø11 shank measured ~17 mm³ vs ~1700 expected), but
   🔴 **the mechanism this entry claimed — «the narrow band excludes the solid core» — is FALSE,
   falsified 2026-09-12 by `dotnet run -- probe <voxel>`:** a *buried* cylinder
   (`max(r − R, |z − z_c| − L/2)`, closed on every side inside the bbox) renders through the very
   same ctor at **99.7–99.8 %** of its analytic volume, at both 0.33 and 0.34 mm. What actually
   hollows a body is a field left **OPEN at the bbox caps** — an unbounded radial field is still
   «inside» there, so `volumeToMesh` yields an open tube, `CalculateProperties` rebuilds a level set
   from a non-watertight mesh, and the interior is gone. The gyroid dodges it not by being
   thin-walled but because `BoolIntersect(envelope)` closes it. 🔑 **Consequence worth having: a
   closed SDF solid is ALLOWED**, which the old rule forbade — and that is exactly what a single-field
   «gyroid + monolithic rod» would need. Keep `voxConstruct` as the default anyway: it is simpler and
   cannot be got wrong by forgetting to close a field.
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
    `NotesLines`; an unset `CAD_REV` gets its own actionable `UNTRACKED (set CAD_REV=…)` in `Program.cs`); the notes field-set is FIXED, so an absent field prints
    `Post-process: NOT SPECIFIED IN CEM` instead of removing its own line; a one-sided tolerance prints
    each side separately (the `?? 0` that rendered `bore: 0.1/0 mm` — a zero minus-limit, i.e. the
    TIGHTEST possible, invented — is gone); a NAMED feature with no limits still renders (this is what
    made `cathode_flange.json:shank_dia` reappear); the Ti-coin canvas height is COMPUTED from its content
    (a one-time retune 560 → 620 came first, pin `A_Long_Note_Grows_The_Canvas_Instead_Of_Falling_Off_It`); and title-block cells cut at a measured budget **and say
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
    🔴 **THIRD member of the class, 2026-09-11, and it is a different shape from the two above: not an
    invented VALUE but an invented PROVENANCE.** `ToleranceLines` appended a hard-coded «(Lamé,
    E_PEEK-aware)» to the interference line, while `zone2_sleeve.json`'s own `fit` string two lines earlier
    says the same 5–34 µm is ISO 286 — which is the truth (`tools/in_silico/lib/constants.py`: H7 0/+18 +
    r6 +23/+34 on Ø11, i.e. the H7/r6 read carried under an s6 label; class — open, `00_07` HW.3; Lamé CONSUMES
    that band to compute a contact pressure, it does not produce one).
    Canon `01_01 §4.2` makes it expensive rather than cosmetic: it requires the drawing's µm to come from
    the Lamé window and explicitly NOT from a blind ISO 286 lookup — so the sheet printed the rejected
    source under the required source's name. **It hid because `zone2_sleeve` is the only manifest that
    fills those fields and had no `draw` kind**, i.e. the defect was latent in an emitter nothing ever
    exercised. 🔑 Two rules out of it: **this tract states QUANTITIES, never where they came from** —
    provenance is engineering text and lives in the CEM like every other word on a sheet; and **shipping a
    carrier for data that never travelled is a DIAGNOSTIC, not just a feature** — a fact that reached
    nobody was checked by nothing. (Whether the band itself should be re-derived → `00_07` HW.3.)
    ⊕ Same pass, same family: the title-block SSOT row was passed RAW past `Cell`, so it overran the
    155 px value column on `mechanical_lock.zone1.json` for weeks — invisible because the frame-fit pin
    measures the CANVAS, not the grid — and walked clean off the canvas at the first longer manifest name.
    The untruncated path now rides the footer and `Cell(…, ptr: "→ FOOTER")` is true. **A pointer may only
    be written once the place it points to really holds the value.**
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

    ⊕ **A loud absence of a SIZE that has no nominal anywhere is a NOTE, not a tolerance row** (2026-09-13). A
    named `tolerances.features` entry prints `+NOT SPECIFIED / -NOT SPECIFIED` — i.e. a ± band around a nominal the
    sheet is assumed to show elsewhere. That fits `bore_dia` (its Ø is drawn) and lies for the flange's channel
    ENTRY RADIUS, whose value is the unknown itself; so that requirement rides `notes.post_process` with
    `RADIUS VALUE: NOT SPECIFIED IN CEM`, and no numeric field was invented to hold a nominal.
    🔑 **Reflex when touching `Drawing.cs`/CEM (unchanged by the fix — it is what PREVENTS the next one):**
    ask "what does a NULL here print on a factory drawing?" — and prefer a loud `NOT SPECIFIED IN CEM`
    over a plausible default. ⊕ Second half, bought by the same pass: **a drawing has TWO readers with
    different eyes** (human SVG ⊥ machine DXF), so any change to notes/title-block must be checked in
    BOTH — every symptom above was invisible in one of them. ⊕ Third half, bought twice (`4f5064db` build
    orientation · `cc0884d0` r6 under an s6 label): **before a sheet orders X, grep
    `docs/00_07_Action_Plan_Tracker.md` for an open ⚖️ about X — if one exists, print NOT SPECIFIED or ask both
    branches; a sheet must not settle a verdict by what it prints.**
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
    was deleting WAS the sheet wall. `stepped` is untouched by that verdict (third branch) and reads **75.4 % since the welded branch landed 2026-09-18** (71.0 between the 2026-09-13 envelope fix and that day) — the 71.8 in the list above is the same part sampled on the rudimentary bore.
    🔴 **The golden tolerance on this field (±0.003) is NARROWER than the instrument's own grid-phase scatter on `stepped` (≈0.006 across grid-origin shifts, measured 2026-09-13)** — so a change that only moves the sampler's ORIGIN reds `stepped`'s golden with no change in geometry. Read such a red as the instrument first; a real geometry change shows up as a Δ that is STABLE across phases (the envelope fix: −0.0078…−0.0079 on four phases), which is how the two were told apart.
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

14. 🔴 **A bare `fea --fit` OVERWRITES a canon-pinned cache with a DIFFERENT SPECIMEN, because the filename carries the RESOLUTION and not the SIZE** (found by the closing sweep, 2026-09-12). The lattice form writes `cache/fea/gibson_ashby_fit.network.s<steps>.json` — topology + steps-per-period only — while its defaults are `--cells 3 --steps-per-period 16`, and every committed row was measured at **two** cells a side. So an un-flagged run lands squarely on the file canon's `період/16` row is pinned to, from a three-cell cube. ✅ `fea_canon_sync` now asserts the specimen and says so by name, but **the guard names the overwrite, it cannot prevent it**: reproduce a quoted row with its FULL flag set (`--cells 2 --steps-per-period 32`) and read `git diff tools/cad/cache/fea/` before committing — an exploratory run is byte-indistinguishable from a re-measurement. ⊕ A probe on an UNPINNED divisor (e.g. `--step-div 11`, used 2026-09-13 to price the step-equalisation leg) overwrites nothing, yet still drops an untracked cache in that directory — and the `Docs` band then refuses to run over an untracked in-scope file. Move the probe's cache out of the tree before the band: it is a phantom, never a commit. ⊕ The PART form is safer by accident, not by design: its name carries `--step-div` (`.d7`/`.d10`), so a default run creates a NEW `.d12` file instead of landing on a pinned one (the `--with-rod` segment went with the verb on 2026-09-18). 🔴 **And the THIRD way the cache and the specimen part company has nothing to do with flags: the cache is right for its day, and its day passed** (2026-09-18). `gibson_ashby_fit.anchor_zone1_pine.d7/.d10/.d32` were measured on an annulus whose INNER radius was the printed rod surface, Ø1.0 (⚠️ not the Ø1.35 cathode channel — two diameters on one axis, and this sentence grabbed the wrong one on its first writing); the welded branch took the core out and no verb here rebuilds that body. ⛔ The canon↔cache guard is blind to this BY CONSTRUCTION — both halves went stale together, so the pair stayed self-consistent and green (`guard-craft` #177). Carrier now in place: a pre-A cache still carries `with_bus_rod`, a post-A run does not emit the key at all, and `fea_canon_sync` ties that fingerprint to the «знесена гілка» marker in the canon row BOTH ways — so when you do re-run, the gate will tell you to delete the caveat. **Price of the re-run, measured: `.d7`/`.d10` minutes, `.d32` ≈ 8 h Release** (`00_07` HW.1). 🔴 **That accident covers `--fit` ONLY (verified in `Program.cs`, 2026-09-14): the plain part verb names its cache `{cem.Name}{.with_rod}{.h<µm>um}.json` — no step divisor, no `--sweep` — so a one-row `fea cem/anchor_zone1.pine.json` OVERWRITES the pinned four-row sweep.** ⛔ And one cache in that directory is FROZEN EVIDENCE that no verb can rebuild — `anchor_zone1_pine.printed_core_branch.json`, the pre-welded-branch annulus canon quotes the rod's +9 % against: losing it turns a canon number into prose. Run the pinned command in full, or move the cache aside, and read `git diff tools/cad/cache/fea/` before committing. 🔑 **Portable: a cache filename must encode every axis along which the canon table's rows differ — the axis missing from the name is where the overwrite goes quiet.**

13. 🔴 **Every numeric field of every `cem/*.json` must carry a DECLARED GROUND, and this is a HARD gate since 2026-09-12 — adding a field without one reds `docs.yml`** (`scripts/cem_provenance.rb`, home `tools/cad/cem/_provenance.json`, canon [`01_02 §6`](../../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), `00_07` HW.48).
    ⚖️ Founder ratified the CARRIER, not the inversion: a full requirement-driven CEM (`porosity ← E_target`, `wall_param ← porosity`) was REFUSED as «heavy» — it touches every SKU and every gate for a property that is cheaper to get another way. So the ground lives BESIDE the value, in `tools/cad/cem/_provenance.json`, which no C# glob parses because it carries no `kind` — `Cem.ManifestFiles` filters on that absence, never on the filename; the `_` prefix only steers `cem_provenance.rb`.
    **What to write when you add a field.** One of five classes — `requirement` (an external requirement we did not choose: a standard's table, a vendor floor, a CODIT wound) · `derived` (computed; `from:` must name WHAT from) · `design` (a design point or worked example hardened into a number — legitimate, but it must be NAMED) · `placeholder` (not yet a decision; bench/RFQ/verdict) · `superseded` (a verdict retired this branch and the application never landed; the number stands and is NOT current) — plus a non-empty `from:`, and any `NN_NN` you cite must resolve.
    🔴 **Two traps the inventory itself paid for, and both are about the RECORD rather than the number.** (a) **A record on `kind` covers two PARTS.** `mechanical_lock` is Zone-1 (shank **Ø11**, a frozen founder dim) and Zone-3 (shank **Ø9**, an HW.8 placeholder), with `bore_diameter_mm = 0` in the first as a SENTINEL for «solid, the bus IS the core» against a real Ø1.35 in the second. One record would promote a placeholder to a decision on a manifest that PRINTS on the factory DXF — so the lookup is `name` → `kind` → `*` → nested, and you pick the tier consciously. ⊕ **Second instance, and it hid longer: `anchor_zone1.outer_diameter_mm` sat on `kind` as «shaft Ø11 frozen» while three of seven SKUs are Ø10 / Ø12 / Ø13 (split into `name`-tier records 2026-09-13, `00_07` HW.26) — when a `kind` record states a VALUE, check that every manifest of that kind carries it.** (b) **A number can be classified and have NO ground anywhere.** Several radome fields are exactly that (lug COUNT · lug radius · socket clearance · cavity height · O-ring gland fill): canon either never states them or quotes them BACK from the CEM, which is a circular ref and therefore an absence. ⛔ Do not carry a COUNT here — «four of eleven» stood in three homes at once and was wrong in all three; `ruby scripts/cem_provenance.rb` prints the live list. Declare it with `canon_ground: false` **and name the tracker item that owns closing it** — the gate requires the owner, because an undocumented shipped number without one is how it stays undocumented. Default when the key is absent is `true`; a silent omission must not buy the exemption.
    ⛔ **Declared ceiling, and no gate closes it:** this judges the PRESENCE of a ground, never its TRUTH. `from: «canon 01_01 §5.2»` is green whether that section carries the number or a different one — the exact miss that cost `rf_clearance_min_mm` (the address was real, the clause said `≥ 8`). Before citing a section, READ the clause; and if canon gives a range or a minimum and you took an end, say which end and that it IS an end.
    🔑 **Worklist mode is separate and exits 0** (`--missing`, by file), because the roster of what is still unclassified is a task for a session that has time, while the verdict must stay a one-line loud stance. ⊕ The gate is registered in `00_06 §3` AND as a `docs.yml` step — `guard_registry_sync` holds both directions, so they move in ONE commit.
15. 🔴 **A direction or a sign in a CEM field is read in TWO frames — the author's assembled/world view and the code's part-local frame — so pin the FUNCTION in the part's frame, never the sign** (`00_07` HW.26, 2026-09-13). `01_01 §4.3` A gives the Zone-3 barbs «the opposite lean», which is how the ASSEMBLED anchor looks: two parts pressed into one sleeve from opposite ends. `CathodeFlange.ShankCem` applied `BarbDirection = −1` in the flange's OWN frame, where z = 0 is already the end that enters the PEEK first — a second mirror, so the steep face met the PEEK first and only the shallow ramp resisted pull-out. Both tests were green: one pinned the mirror identity, the other the sign itself; neither could fail on a frame error. The fix removed the knob (it had no legitimate second value) and pins the physics: `MechanicalLockTests.Every_Shipped_Lock_End_Presents_Its_Shallow_Ramp_To_The_Peek_First` walks in from local z = 0 on both lock manifests AND on the shank the flange actually builds through `ShankCem`, where the reversal lived. **Reflex for any orientation-bearing field** (lean · handedness · thread direction · build direction · any ±1): name the frame in the field's comment, write the test as the physical consequence in that frame (what meets what first), and put the BUILT part in the roster — a pin on the value is vacuous against a frame error.
16. 🔴 **A constant-period lattice sampled at a step that divides its period is PHASE-LOCKED — and `--step-div N` takes the step FROM the period, so on a constant-period part EVERY divisor is such a step, by definition** (found 2026-09-14, when the graded-pair bracket of `00_07` HW.33 collapsed). The sampler puts every cell's points at the same phases, so a wall level moves the voxel model only where it crosses one of the few field values sampled there: on `graded_porosity` (period 2.0) with the wall held uniform, ten walls from −0.60 to 0.40 at `/4` gave THREE porosities, and at `/8` the walls −0.15, −0.08 and +0.10 sampled to ONE grid, cell for cell. `pine`, whose period is graded 2.5 → 2.0, drifts the phase with radius and gave ten. The radial pre-check does not cause the lock, it narrows the way out: a radial sweep needs a step that is a fraction of the DIAMETER and not of the period. ✅ Carriers: `VoxelFea.PhaseLockCells` (a warning line in `fea` and `fea --fit`) · `VoxelFea.IdenticalSweepGrids` (both `--fit` forms now sample every wall BEFORE solving and refuse a collapsed sweep in seconds; pins in `VoxelFeaTests`) · **`--step-mm H`** on the part verbs — a step taken from the diameter that does not divide the period (11/50 = 0.22, 11/60), cached as `.h<µm>um` so it can never land on a pinned `.d<N>` file. ⛔ A merely COARSE staircase is NOT refused: it reads as scatter in ρ (the cube's `s16` fit carries ±10 % residuals on neighbouring points, falling with steps per period), and the cube is locked by construction — which is why the canon table quotes it at three steps per period, with R² rising alongside. 🔑 **Portable: a sampling grid commensurate with the structure it samples measures the grid's phase set, not the structure — before sweeping a level, ask whether the level can move the sampled values at all.**

17. 🔴 **`out/` is OUTSIDE every gate we own, and that is where the VENDOR's copy lives** (measured 2026-09-17, HW.24). The coupon attachments — per-alloy STL + DXF — are built into `tools/cad/out/`, which is gitignored, so no test, no band step and no `git diff` can see them age. Found by accident while regenerating: `out/ti_coin.stl` was built **2026-06-20 09:08** and the coin's diameter changed Ø10 → Ø16 the SAME DAY at 17:19 (`0ca7eec5`) — for three months the file that would have gone to a print bureau was a different part. The gallery SVG is pinned (manifest SHA in the title block) and the CEM is pinned to canon, but the artefact the vendor actually receives is pinned by nothing. **Reflex: before any dispatch, rebuild the attachments from a clean tree and CHECK them against the manifest** — `dotnet run -- draw cem/<x>.json` + `build`, then verify the geometry you are shipping (an STL's bounding box is three `struct.unpack` lines; ours reads ±8.0 mm on the disc, 1 mm thick, eyelet to 11.2). ⛔ Do not infer freshness from the file being present: `out/` never fails, it only lies quietly. 🔑 Portable beyond CAD: **the copy that leaves the building is the one no gate is watching** — name it explicitly in the dispatch checklist, or it ships stale.

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
  sheet-era 1.0 lands network at 50.2 % porous / **≈23 GPa formula-only under the MEASURED `C` 0.983 · `n` 2.242 — ⚠️ a Gibson-Ashby prediction with NO axis: canon reports apparent stiffness per axis (×0.79 axial / ×0.56 radial, re-measured 2026-09-18 on the welded branch), and the 13–15 GPa requirement was withdrawn 2026-09-17, so never quote a bare GPa figure as a target
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
- **Welded bus wire (`01_01 §1.4` + `§3` step 1b, HW.1/HW.34, SHIPPED)**: `bus_rod_diameter_mm` declares the WIRE. ⛔ **It is NOT printed with the anode** — ⚖️ founder 2026-09-18 applied the welded branch in CAD: the part has no core (lattice to the axis), `Zone1Anode.BuildMonolithic`/`BusRod` and `fea --with-rod` are REMOVED, and the wire body lives in `AxialStack` starting at the anode's TOP FACE (`BusWireBottomZMm`), where the weld seam and the cantilever root coincide. The golden baselines and the sub-floor shares were re-measured the same day (`01_02 §1.3`); the part-level FEA rows still quote the pre-A specimen and their re-run is a named leg (`00_07` HW.1). ⚠️ **Why the route matters even though the CAD now only models the RESULT:**
  the ratified fabrication is a WELD (⚖️ 2026-09-10 — an as-printed rod carries `ENDURANCE_OVER_YIELD ×
  AS_PRINTED_DERATE`, a welded cold-drawn wire does not), and until 2026-09-18 the generator drew the
  rod as a printed core, i.e. an STL of the branch that verdict removed. Consequence you will hit: the rod's tolerance and `Sa` come from a WIRE spec canon does not
  carry, not from an LPBF surface. ⚖️ **RATIFIED 2026-09-12: both are a VENDOR INPUT entering through the Validation Gate (`00_06 §0`), not a number we pick** — so this is an RFQ answer waiting, no longer an open judgment (`00_07` HW.34). ⛔ And the half that verdict REJECTED is the one that will tempt you back: "a drawn wire is smooth, so liner wear is solved" — the specific wear rate has no number and no literature figure anywhere in this tree (since 2026-09-12 `55` §`wear_budget` bounds the rate the pair may have, which is a budget, not a measurement), and FMEA `#21` is one of the register's top rows (RPN 288; `#4` = 360 is the highest). The CEM still has no field for either. ⛔ `Zone1Anode.BuildMonolithic` = `Anode` + `BoolAdd(BusRod…)` was the printed-core build and is GONE (2026-09-18); `Zone1Anode.Build` is the gyroid alone. 🔑 **Porosity stays a property of the gyroid**
  (`Anode` + the annulus envelope, `InnerRadiusMm` = rod surface) — the rod is SDF-invisible, so connectivity
  /porosity gates are untouched; `verify` separately MEASURES the fused rod volume (`ReportAnchor`, ≳π(r)²·L).
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
  — solid `BaseCylinder().voxConstruct()` + thin barb-ridge `BoolAdd` + groove-ring `BoolSubtract` + a
  central bore (`0` ⇒ SOLID monolithic anode shank, `01_01 §1.4`; `Ø1.35` ⇒ the cathode channel the bus rod
  threads) (gotcha #9 — never the SDF ctor for the solid). Tooth is over-specified in `01_01 §4.3` → keep
  α/β + h, DERIVE base = h·(cotα+cotβ), MEASURE in `verify`. Self-support holds only for a SEPARATE print laid
  gentle-ramp-down (`01_01 §4.3 A`; `01_02 §1.6` says only tip-down); DIN-471 groove = real shaft dims (not the off-spec canon 0.8×0.6). In the
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
  capsule-end never touched: Zone1↔2 line-to-line (real +interference = the press-fit band on bench — the H7/r6 read carried under an s6 label; class — open, `00_07` HW.3) · **Zone2↔3 =
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
  «(Lamé, E_PEEK-aware)» suffix; that invented provenance is gone (gotcha #11), the engineering verdict is
  open in `00_07` HW.3. **Do not read this bullet as «the drawing carries Lamé µm» — it carries what the CEM
  says, and the CEM says ISO 286: the H7/r6 read carried under an s6 label, class NOT SETTLED (`00_07` HW.3).**
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
  screenshot (gold Ti-metallic material); `section <cem>` = a −X cutaway (shows the bus rod through a dense gyroid
  where `ColorFloat` alpha can't). Display-gated (gotcha #10); output → `out/*.png` (native TGA → `sips`). The
  presentation gallery `docs/images/cad/` is NOT SSOT (`tools/cad/scripts/render_gallery.sh` rebuilds it)
  — ⚠️ but see the drawing bullet above: **not-SSOT is not a licence to lag**, and the PNGs there have no
  pin at all, so a stale render is invisible to everything.
- **Measure apparent stiffness** — `dotnet run -- fea <cem> --sweep` (part) · `fea --ladder` (the same lattice as an n-cell cube, the material-scale control) · **`fea --fit` (the Gibson-Ashby `C` and `n` fitted over a `wall_param` sweep — TWO specimens on ONE flag: no cem argument ⇒ the lattice cube, a cem argument ⇒ the shipped annulus, `fea cem/anchor_zone1.pine.json --fit --step-div 10`)**. Reported as a fraction of `E_solid`, because the Zone-1 alloy is bake-off-gated (00_07 HW.24) and the candidates span 80–186 GPa. ⛔ A single row is an UPPER bound (staircase boundary + fully-integrated hexes, both stiff-biased), so never quote one without its sweep; and the subject is the PRINTED part — the lattice to the axis. ⛔ `--with-rod` was REMOVED 2026-09-18 with the printed-core branch (⚖️ 2026-09-10, applied 00_07 HW.1): it measured a body the factory never receives, and canon quoted its «+9 % axial» as a property of the part. ⚠️ Every part-level row in `cache/fea/` still carries the PRE-A specimen (annulus from the rod surface) until its re-run lands — the lattice cube and the ladder are unaffected, they never had a core. 🔴 **`C` and `n` are MEASURED since 2026-09-12, not assumed** — 0.983 / 2.242 on the lattice (cube, period/32) and 1.069 / 2.269 on the shipped annulus (period/10) — **so the textbook `n = 2` is retired AXIALLY and the member that was wrong there is the EXPONENT, not `C`.** 🔴 **And WHICH member is wrong is a property of the AXIS: the radial fit of the same part (`--with-radial`, period/10) gives `n` ≈ 1.95 at `C` ≈ 0.54 — on the load-bearing axis the exponent is textbook and the coefficient departs** (`01_01 §5.2`). ⛔ `--with-radial` is REFUSED on a step that does not divide the diameter (an odd divisor on Ø11): the grid gains an empty column and the radial load centre walks a quarter step off the axis (`VoxelFea.RadialLoadCentreOffsetMm`); the axial fit is unaffected and still runs there. ⛔ **On a CONSTANT-period part every `--step-div` is PHASE-LOCKED** (gotcha #16 — the divisor takes the step from the period): sweep such a part with `--step-mm` (a step from the diameter, not from the period), and expect the verb to refuse a sweep whose walls sample to one grid. ⛔ **Never compare a single-density `C` across geometries: the SAME cube reads 0.71 · 0.80 · 0.77 at 16 · 24 · 32 steps, i.e. the full width of the «cube↔part gap» canon used to call non-physical. Compare FITTED pairs or nothing.** (The cube is locked by construction, so part of that wander is plausibly its porosity staircase — not separated from the mesh-stiffness term, and not measured apart.) ⛔ **And this verb does not produce what a physical test returns by default:** ISO 13314's comparable quantity is the **elastic gradient** — the secant of an UNLOAD/RELOAD hysteresis loop between 20 % and 70 % of plateau stress — never the quasi-elastic gradient, whose role in the standard is to locate the strain zero; so a printed-specimen order without an unloading cycle comes back with nothing to compare against, and any comparison must name a POINT on the curve. ⊕ **Print thickening is a SENSITIVITY, never a body: `fea <cem> --dilate downskin|iso`** — the offset is a FACE displacement (segment LENGTH along +BD in the part frame · ball RADIUS, so a ligament gains 2R); a shifted sample takes metal only from inside the part body while the origin is never clipped, which is what lets the zero row reproduce the pinned `/12` row bit for bit; caches are `dilation_sensitivity.*`, one file per row. Numbers, the literature check and the declared ceiling → `01_01 §5.2`; the table is machine-held by `ruby scripts/fea_canon_sync.rb` (HARD in `docs.yml`, fourth layer).
- **Check resolution adequacy** — every declared thickness/gap against the voxel its own assembly asks for, `2·voxel` represented / `4·voxel` volume-honest. Hard carrier `ResolutionTests`, operator line inside `verify`. 🔑 Walks the PARSED RECORD TREE: a composite manifest declares a handful of numbers and inherits dozens of `Cem.cs` defaults written for a PART voxel — that inheritance is the defect class, not a detail.
- **Local-verify** (`export PATH="$HOME/.dotnet:$PATH"` first — the SDK is NOT on PATH, and «dotnet is not installed here» has already been asserted falsely once, 2026-09-10): `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1) → `dotnet run -- draw cem/<x>.json` (SVG+DXF → out/) → `dotnet run -- fea cem/<x>.json --sweep` (pure-managed like `draw`; ⚠️ it writes into the COMMITTED `cache/fea/`, unlike `out/`, so a run has a diff)
  → `dotnet test`. CI = enterprise 2-job `cad_smoke.yml` (logic = Linux pure-xUnit hard [incl. draw/DXF]
  + render = macOS build-hard + verify best-effort, Library.Go 139 headless).
  🔴 **`dotnet run` builds DEBUG by default, and for an FE run that is a ×4.1 tax — measured, not assumed** (2026-09-15, on the pinned `.d7` part fit: **73 s at `-c Release` against 298 s in Debug**, same machine). ⛔ The reason it is safe to take: the Release run reproduces the committed cache **bit for bit** on every axial cell and on `C`/`n`, so the config is a cost axis and not a numeric one — verified by re-running `.d7` into a copy and comparing field by field. 🔑 **Where it actually bites is the ESTIMATE, not the run:** the «~1.5 доби CPU» that priced the `--step-div 32` leg in `00_07` HW.33 was extrapolated from a Debug probe, and the real Release run took **7 h 50 m**. So a cost quoted from a probe carries the probe's BUILD CONFIG inside it, invisibly — when you price a long run from a short one, say which config you measured. ⊕ For a run of hours: `nohup caffeinate -i` (a sleeping Mac stops it), and run the binary from a COPY (`cp -R src/SilkenCad/bin/Release/net9.0/. out/<name>_bin/`) — a parallel agent's `dotnet build` in this tree would otherwise swap the DLLs under a live process. The cache is written only at the END; the per-wall rows print as they solve, so redirect stdout to a durable log or a crash at hour six leaves nothing.
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink (vendored LEAP source, kept out of owned code).
