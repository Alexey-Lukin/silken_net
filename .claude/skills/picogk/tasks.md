# PicoGK — task recipes (the bodies)

> **Companion file of the `picogk` skill. Open it before you START any CAD task** — a part or SKU, the
> anchor geometry, the bus wire, a lattice, a drawing, a render, an FE or resolution run, `verify` or
> `converge`, an assembly audit, a submodule bump. Each recipe carries its live verdicts and traps inline;
> the numbered gotchas they cite (`gotcha #N`) are in [`gotchas.md`](gotchas.md).
>
> ⛔ **Not numbered, on purpose:** a second numbered series in this skill would make every bare
> `picogk #N` citation ambiguous (the `deploy` split paid exactly that). Cite a recipe by its bold name —
> `picogk` `tasks.md` «Welded bus wire».

- **Add a part / per-species SKU**: write `cem/<name>.json` (with a `kind`) + a generator in
  `src/SilkenCad/` + wire the `build`/`verify` switch in `Program.cs`; give every numeric field a declared
  ground in `tools/cad/cem/_provenance.json` (gotcha #13 — HARD in `docs.yml`); `dotnet run -- verify`. A new anchor
  SKU also needs its baseline (`verify --write-golden` — without a golden it passes unpinned) and meets the
  `AnchorTests` shipped-manifest pins (topology · bus-rod field · coating restriction · tolerance block).
- **Change anchor geometry**: edit `cem/anchor_zone1.*.json` (Ø, period, wallParam — and `bus_rod_diameter_mm`, which declares the WELDED WIRE, an assembly part: the anode is printed with NO core and `Zone1Anode.InnerRadiusMm` returns 0 for every manifest, pinned by `AnchorTests.The_Printed_Part_Carries_No_Core`. The wire field still has to BE there — `Every_Shipped_Anchor_Cem_Declares_Its_Bus_Rod_And_No_Bore` reds on a manifest that omits it or carries a bore key, which would otherwise evaporate on parse).
  Geometry numbers and the founder decisions on them are owned in canon (`01_01 §5`); the open anchor-geometry legs live in `00_07` HW.33; **MEASURE
  porosity after** (gotcha #4). Render via `Zone1Anode.Anode` (the ctor route, gotcha #1).
  ⚖️ **Topology = `network`** — every shipped `anchor_zone1.*` but `stepped` declares it; `stepped` is a
  separate, already-decided THIRD branch (`ZonedGyroid`).
  🔴 **The live rule is that `wallParam` NEVER carries across a topology flip, and it is not cosmetic:**
  the param is a BAND on sheet (`|eq| < 0.5·w`) and a LEVEL on network (`eq < 0.5·(w−1)`), so a sheet-era
  value lands network at a different porosity AND stiffness. Canon reports apparent stiffness per axis and
  carries no GPa target (`01_01 §5.2`): a formula-only GPa figure under the canonical `C`/`n` pair (axial only —
  the radial axis has no formula pair) is an estimate that must be marked as one — never quote a bare GPa
  figure as a target. Re-solve against the
  porosity target FIRST: on network the porosity is a function of the LEVEL, not of the period, so one
  `wallParam` serves every species SKU (curve and working point: `01_02 §6`; per-SKU values: the goldens).
  🔴 **Two traps this branch arms, both silent.** (a) The `graded_porosity` SKU grades
  the wall itself, and on network its rim needs a NEGATIVE level; the old
  `GyroidWallParamRim > 0f` sentinel swallowed that back to the core value, i.e. the manifest would state
  a gradient and the geometry would be constant, with nothing red. The field is nullable now — but the
  general form is the lesson: **a `> 0` sentinel encodes «≤ 0 is meaningless», and a topology change can
  make ≤ 0 ordinary.** (b) The CLI `scan` swept `wallParam` from 0.2, so the ratified working point sat
  OUTSIDE the sweep and the command would have answered "no working window" on a sound part; the bounds
  are topology-dependent now (`WallScan`; the measured network window: `tools/cad/README.md`).
  📐 The specific-surface price of network is measured per SKU (`01_01 §5.5`) — quote that, not the rounded «~2×».
- **Welded bus wire (`01_01 §1.4` + `§3` step 1b, HW.1/HW.34, SHIPPED)**: `bus_rod_diameter_mm` declares the WIRE. ⛔ **It is NOT printed with the anode** — ⚖️ founder 2026-09-18 applied the welded branch in CAD: the part has no core (lattice to the axis), `Zone1Anode.BuildMonolithic`/`BusRod` and `fea --with-rod` are REMOVED (gotcha #14), `Zone1Anode.Build` is the gyroid alone, and the wire body lives in `AxialStack` starting at the anode's TOP FACE (`BusWireBottomZMm`), where the weld seam and the cantilever root coincide. The golden baselines and the sub-floor shares were re-measured on the welded body (`01_02 §6`). ⚠️ **Why the route matters even though the CAD now only models the RESULT:**
  the ratified fabrication is a WELD (⚖️ 2026-09-10 — an as-printed rod carries `ENDURANCE_OVER_YIELD ×
  AS_PRINTED_DERATE`, a welded cold-drawn wire does not). Consequence you will hit: the rod's tolerance and `Sa` come from a WIRE spec canon does not
  carry, not from an LPBF surface. ⚖️ **RATIFIED 2026-09-12: both are a VENDOR INPUT entering through the Validation Gate (`00_06 §0`), not a number we pick** — an RFQ answer waiting, not an open judgment (`00_07` HW.34). ⛔ And the half that verdict REJECTED is the one that will tempt you back: "a drawn wire is smooth, so liner wear is solved" — the specific wear rate has no number and no literature figure anywhere in this tree (`55` §`wear_budget` bounds the rate the pair may have, which is a budget, not a measurement), and FMEA `#21` heads the register — scores live in `docs/protocols/hardware/fmea_fmeca_register.md` §1, never here. The CEM still has no field for either. 🔑 **Porosity stays a property of the gyroid**
  (`Anode` + the FULL cross-section envelope, `InnerRadiusMm` = 0) — porosity is measured against the
  whole Ø; the wire is not in the part, so `verify anchor_zone1` measures no rod.
  ⊕ **That is the ONE inner radius in the tree:** `build`, every topology metric
  (`Connectivity.SampleAnchor`, and through it the as-printed opening and the wall scan), per-shell porosity
  (`Validation.ShellBoundariesMm`), the FE sampler and the anchor drawing all read `Zone1Anode.InnerRadiusMm`.
  Pin `AnchorTests.Every_Anchor_Reader_Samples_The_Inner_Radius_Build_Cuts` judges the three SAMPLERS (topology · FE ·
  per-shell) against the radius `build` cuts — never against another reader, so two readers wrong the same way still
  red; the drawing calls the same function but is not in that pin.
  Cathode keeps its channel (`mechanical_lock.zone3`/flange bore); anode shank `bore→0` (solid). F3 audit =
  `AxialStack.BusRodClears` (rod + 2·liner **<** channel), and **F4
  `AxialStack.LinerCoversChannel`** — the liner must cover the channel END TO END, not merely fit it by
  diameter. ⛔ F4 exists because F3 declares that blindness and cannot close it: a tube SHORTER than the
  channel passes F3 green while leaving bare cathode metal against the bus at one end. Its axial extent
  comes from `bus_liner_protrusion_mm` (⚖️ 2026-09-12: the lower end protrudes into the PEEK
  gap, so the bore EDGE meets the tube's flank instead of its end face). ⚠️ **The comparison is STRICT**
  (00_07 HW.34, clearance verdict): at the pre-verdict channel the sum passed at ZERO nominal clearance,
  i.e. blessed a tube whose outer Ø equals the bore; it now fails exactly that, pinned by
  `Zero_Nominal_Clearance_Is_Not_A_Pass__The_Pre_Verdict_Channel`. ⛔ Its declared ceiling did NOT change:
  it still judges NOMINALS, and the diametral band of the machined bore is an open vendor question — green
  here is not proof that a real pair mates.
- **Graded gyroid (v2, SHIPPED)**: own SDF, **NOT** LEAP `ImplicitModular` (`FunctionalScaleTrafo`
  is a hard-coded Z-demo, not radial; LatticeLibrary upstream is DORMANT — our pin IS `HEAD main`, so
  re-check it by `git ls-remote`, never by age; the one that IS behind is `LEAP71_ShapeKernel` — skill
  `dependency-update`). Three CEM-driven axes
  in `Zone1Anode`: `GradedCartesianGyroid` (continuous period+wall taper) + `ZonedGyroid` (stepped
  zones). Pick by goal — continuous-gentle (≤~0.8× period ratio, gotcha #5), `GyroidWallParamRim`
  porosity gradient, or `topology: stepped` for a STRONG ~2× pore contrast — ⛔ **µ-LPBF only since ⚖️ 2026-09-17: `stepped` is NOT an SLM pick** (most of its lattice metal sits below the SLM floor BY CONSTRUCTION — share: its golden, `01_02 §6`; revisit trigger: `01_01 §5.5`). **MEASURE** porosity.
- **Mechanical-lock barbs (`MechanicalLock.cs`, SHIPPED)**: asymmetric ratchet `R(z)` on the Ti shank
  — solid `BaseCylinder().voxConstruct()` + thin barb-ridge `BoolAdd` + a groove-ring `BoolSubtract` ONLY where
  `MechanicalLock.HasGroove` (which end keeps one: `01_01 §4.3 B`; a zero as the decision: gotcha #0a) + a
  central bore (`0` ⇒ SOLID anode shank, no channel — the bus wire is welded on the anode's top face,
  `01_01 §1.4`; `Ø1.35` ⇒ the cathode channel the wire threads) (gotcha #9 — never the SDF ctor for the solid).
  Tooth is over-specified in `01_01 §4.3` → keep α/β + h, DERIVE base = h·(cotα+cotβ), MEASURE in `verify`.
  Self-support holds only for a SEPARATE print laid gentle-ramp-down (`01_01 §4.3 A`; `01_02 §1.6` says only
  tip-down); where a groove IS cut it takes real DIN-471 shaft dims. In the lock's own frame the shallow α ramp
  faces z = 0 — the end that enters the PEEK first — on BOTH ends, with no direction knob (gotcha #15); the
  Zone-1 anode's frame runs the other way (z = 0 = tree side), so an integrated shank is PLACED by rotation; on
  the INTEGRATED Zone-1 body «tip-down» puts the steep face down — open, `00_07` HW.26 G4.
- **Connectivity / verification (ARCH.25)** — CODE VERIFICATION, two independent routes to one topological
  fact (canon `01_02 §6`); validation needs the physical experiment we have not run: `Connectivity.cs` samples
  the CEM SDF → 3-phase grid → 6-conn flood-fill → open-pore (Archimedes) / percolation (EAAE flow-through) /
  solid-island (AM + electrical) / closed-pore (trapped-powder) / specific-surface. Pure-managed → fast
  display-less xUnit. Resolution split: gotcha #8. The `verify` gate adds open≥95% · solid-disc≤2% ·
  percolate axial+radial. Topology-agnostic by construction.
- **Topology-convergence ladder (`converge`, SHIPPED, `00_07` HW.51)**: `dotnet run -- converge
  cem/<anchor_zone1.x>.json --divisors 24,32` samples the same connectivity metrics at each divisor of the finest period
  and writes a committed cache under `tools/cad/cache/topology/`. A probe, never a
  verification — no golden, no OK/FAILED; a rung clamped onto the adaptive floor prints «SAME GRID … proves nothing» and
  a SKU whose rungs all land there prints «NOT A LADDER». Pin `AnchorTests.Every_Committed_Convergence_Ladder_Was_Measured_On_Todays_Sampler`
  recomputes the sampler step from the CODE **and, since 2026-09-20, requires the committed rows to carry the canon
  rungs** (`Program.CanonConvergenceDivisors`, the same constant the verb defaults to) — so a run at other `--divisors`
  now reds naming the SKU and the missing rung instead of silently replacing the ladder. A WIDER ladder passes. ⛔ The
  remaining ceiling: the cache name still carries the SKU only, and the pin cannot tell whether the rows came from ONE
  run — a hand-merged cache with both rungs present passes, so still read `git diff tools/cad/cache/topology/` before
  committing (gotcha #14's class). Numbers → the cache / `00_07` HW.51, never here.
- **Capsule-end assembly (`Assembly.cs`, SHIPPED)**: brings Деталь 3 ↔ Деталь 4 into one frame at the
  bayonet datum (radome lock-groove ↔ flange lugs) via `MeshUtility.voxApplyTransformation` (lift; the
  per-part `Build`s stay untouched) and MEASURES the residual mismatch (radial / bayonet-Z / RF) + models
  the skirt/inboard MATE-Ø candidates. An AUDIT table — `verify` exits on a broken render only; the
  mismatch numbers are asserted by pure xUnit. Canon `02_02 §4.4`. ⚖️ **The reconcile is NOT one bench job:
  the RADIAL half was ratified 2026-09-10** (Ø25 stays, a local internal rim boss carries socket + seal land,
  `skirt` withdrawn because it deletes the sealing face), **and the bayonet-Z half was RATIFIED 2026-09-11**
  (`02_02 §4.4`: lugs on a RAISED COLLAR above the sealing face) — because the mismatch is `t/2 + lockGrooveZ`,
  two positive terms, so no assignment of the frozen dims reaches zero and the lug needs a Z of its own
  (`Assembly.RequiredLugZMm`). ⊕ The two "separate" equations share `Rf + mismatch = cavityH`: lowering
  `lockGrooveZ` pays into BOTH, `cavityH` into RF alone — ⛔ but «raise the cavity» is a REMOVED branch: the
  ratified flat crown moves the headroom the other way, and the RF floor is set from BELOW by the board stack.
  The seal mate is pinned (`Assembly.SealLandBacksTheGroove`, one slot clearance of land each side, strict);
  the boss, collar and crown state → the `Radome.cs` row of `SKILL.md` §Source Files; HW.8.8 is the bench leg that follows.
- **Full axial stack (`AxialStack.cs`, SHIPPED)**: the SECOND integration artifact — brings ALL FOUR zones
  (anode → Zone-2 sleeve → flange → radome) into one axis and MEASURES the **press-fit** interfaces the
  capsule-end never touched: Zone1↔2 line-to-line (real +interference = the press-fit band on bench — band:
  `00_07` HW.3) · **Zone2↔3 = −1.0 mm = the Ø9-in-Ø11 clearance = F1, shank Ø placeholder → HW.8.9** ·
  insertion budget · span. AUDIT table; render uses the Zone-1 **envelope** (solid Ø11 — a press-fit cares
  about OD, not porosity; also keeps the 0.2 mm voxel safe). Reuses `Assembly.Build` +
  `voxApplyTransformation`. Canon `02_02 §4.5`.
  🔑 **`BasePipe`/`BaseCylinder` Z-origin = `[0, L]` from the frame** (grows along +localZ; verified in LEAP
  `Frames.cs` — NOT centred), so stack lifts are absolute; the render overlap sleeve∩capsule is the flange
  SHOULDER on the sleeve top face, not the shank (the Ø9 floats in the bore).
  ⊕ **The Zone-1 insertion is judged against its OWN lock (`00_07` HW.26 G1):** the stack NAMES the lock by
  file (`zone1_lock_manifest`) and never copies its numbers — a nested `MechanicalLockCem` fills absent fields from defaults
  whose contact zone and shank length ARE the Zone-1 lock's, so a wrong or empty copy would print the right window (hence the
  `kind` check in `AxialStack.Zone1Lock`). One home: `MechanicalLock.InsertionWindowMm`; `verify` prints it beside
  `zone1_insertion_mm` and flags an insertion outside it. 🔑 **Pin a detector with the value HANDED IN, never read from
  the default** — a pin asserting that the shipped placeholder stays outside cements the defect and reds the day G1 is fixed.
- **Generate an engineering drawing (`Drawing.cs` / `draw`, SHIPPED)**: `draw <cem>` emits
  **SVG (human) + DXF via netDxf (factory, opens in AutoCAD/Fusion)** — no PDF (scoped in research, never
  built); ⚠️ read gotcha #11 BEFORE touching notes/tolerances — pure-managed, no Library.Go,
  consuming the CEM `ToleranceSpec`/`NotesSpec` (zero hard-coded eng-text; `DrawingStandard` ISO/ASME
  param). Drawing carries fits, GD&T datums, post-process + coating-restriction notes, lattice-spec.
  ⚠️ **«Lamé-µm, NOT a blind ISO-286 lookup» is the canon REQUIREMENT (`01_01 §4.2`), and the shipped band
  does not meet it yet** — `zone2_sleeve.json`'s 5–34 µm is an ISO 286 H7/r6 read (`tools/in_silico/lib/constants.py`),
  which Lamé merely consumes to get a contact pressure. The verdict is taken — no table class, the band is
  solved from the Lamé window (⚖️ 2026-09-18, `00_07` HW.3; its inputs are open). **Do not read this bullet as
  «the drawing carries Lamé µm» — it carries what the CEM says, and the CEM's `fit` says NO TABLE CLASS: the
  5–34 µm is an H7/r6 read kept as the working input, its MIN lies below that window's floor, and the number
  will move.**
  ⛔ **Shipped kinds are NOT listed here** — read `Program.Draw`'s `switch`; phasing and the kinds deliberately
  NOT drawn, each with its ground, live in `tools/cad/docs/drawings_program.md §7`. A kind is meant to carry the
  shipped-CEM DXF round-trip and, if published, a gallery pin — check per kind rather than trusting this
  sentence, and do not count the sha-256 pin as a round-trip: it proves WHICH manifest was drawn and nothing
  about what the sheet carries, so a kind reached only by it ships its notes and fits unverified in the factory
  reader (⛔ test COUNTS quoted nowhere — the roster is `DrawingTests.cs`).
  🔴 **The anchor sheet is the one whose CONTENT is load-bearing rather than its geometry:** `draw
  anchor_zone1` exists to carry the `01_02 §3.6` coating zone-map, whose Zone-1 rows hold OPPOSITE
  permissions (gyroid wall in sap: every dielectric forbidden ⊥ periphery in callus: Zn-HAp allowed) and
  whose dividing surface is in no manifest and is not derivable from the geometry. The sheet therefore
  REFUSES it out loud in both readers, pinned. ⛔ And the lattice is a CALLOUT, never a contour: an honest
  SDF cross-section is available pure-managed and canon `01_02 §6` forbids it anyway (over-drawing a PBF
  lattice promises a precision nobody measures) — so a future «let's sample the SDF» has to argue with canon.
  NORM (why a drawing is derived from the CEM, what it must carry, the loud-absence rule) = canon [`01_02 §6`](../../../docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md);
  research + phase roster = `tools/cad/docs/drawings_program.md`.
  🔴 **`docs/images/cad/*.drawing.svg` is a SECOND artefact and nothing re-runs the gallery for you.** It
  is committed and opens straight from GitHub (a blob-rendered SVG) — i.e. the drawing outsiders see, so a
  lagging gallery publishes exactly the lines a code fix removed. ⚠️ **`wiki:sync` does NOT carry it:** `lib/tasks/wiki.rake` syncs only the canon `NN_NN_*.md` and copies an
  image only where a doc EMBEDS it as `![…](…)`; no canon doc embeds these. Want them on the wiki — embed them
  in a canon doc first. Change `Drawing.cs` or a CEM ⇒ re-run `tools/cad/scripts/render_gallery.sh` (or at
  least its DRAWING loops — ⛔ **read the loops, never a count**: a roster beside a growing script is the
  volatile counter in prose form, and an example gets no exemption from the rule it illustrates) and commit
  the SVGs. A pin reds on the CONTENT drifting apart
  (`Published_Gallery_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame`) and on MANIFEST IDENTITY:
  every sheet prints `cem_sha256` (prefix in the title block → FOOTER, full hash in the footer and the DXF), so
  any byte change to a published manifest — a note or a trailing newline included — reds its gallery row until
  the drawing loops are re-run. ⛔ Declared ceiling: not the sheet's layout bytes, not its `rev` stamp.
  🔴 **`cemSha256:` is an OPTIONAL parameter threaded through one `case` per kind in `Program.Draw`, so the
  compiler will not ask a new kind to pass it** — the carrier is `Every_Drawn_Sheet_Names_The_Sha256_Of_The_Manifest_Bytes_It_Was_Drawn_From`,
  which runs `Program.Draw` itself. Measured: unwiring ONE case reds only that row while every pin that calls
  `Drawing.X` directly stays green. 🔑 A test that hands the emitter a value of its own making proves the
  emitter, never the wiring — so adding a kind means passing `cemSha256:` to BOTH halves.
- **Render / section for presentation (`render`/`section`, SHIPPED)**: `render <cem>` = a PicoGK native-viewer
  screenshot (gold Ti-metallic material); `section <cem>` = a −X cutaway, for the inside `ColorFloat` alpha can't
  show: `section anchor_axial_stack` shows the welded wire (gold) from the weld seam on the anode's top face;
  `section anchor_zone1` = the lattice alone. Display-gated (gotcha #10); output → `out/*.png` (native TGA →
  `sips`). The presentation gallery `docs/images/cad/` is NOT SSOT (`tools/cad/scripts/render_gallery.sh`
  rebuilds it) — ⚠️ but **not-SSOT is not a licence to lag**, and the PNGs there have no pin at all (the
  committed section PNGs still show the retired core), so a stale render is invisible to everything.
- **Measure apparent stiffness** — `dotnet run -- fea <cem> --sweep` (part) · `fea --ladder` (the same lattice as an n-cell cube, the material-scale control) · **`fea --fit` (the Gibson-Ashby `C` and `n` fitted over a `wall_param` sweep — TWO specimens on ONE flag: no cem argument ⇒ the lattice cube, a cem argument ⇒ the shipped part (the lattice to the axis), `fea cem/anchor_zone1.pine.json --fit --step-div 10 --walls -0.40,-0.20,0.00,0.20,0.40,0.60` — the part form REFUSES without `--walls` (gotcha #14))**. Reported as a fraction of `E_solid`, because the Zone-1 alloy is bake-off-gated (00_07 HW.24) and the candidates span a wide modulus range. ⛔ A single row is an UPPER bound (staircase boundary + fully-integrated hexes, both stiff-biased), so never quote one without its sweep; and the subject is the PRINTED part — the lattice to the axis (the removed `--with-rod` and the frozen caches: gotcha #14). 🔴 **`C` and `n` are MEASURED, not assumed** — on the lattice cube and on the shipped part, per axis and per step, and the numbers live in the `01_01 §5.2` table only — **so the textbook `n = 2` is retired AXIALLY and the member that was wrong there is the EXPONENT, not `C`.** 🔴 **And WHICH member is wrong is a property of the AXIS: the radial fit of the same part (`--with-radial`, period/10) keeps `n` near 2 while `C` falls well below 1 — on the load-bearing axis the exponent is textbook and the coefficient departs** (`01_01 §5.2`). ⛔ `--with-radial` is REFUSED on a step that does not divide the diameter (an odd divisor on Ø11): the grid gains an empty column and the radial load centre walks a quarter step off the axis (`VoxelFea.RadialLoadCentreOffsetMm`); the axial fit is unaffected and still runs there. ⛔ **On a CONSTANT-period part every `--step-div` is PHASE-LOCKED — sweep such a part with `--step-mm`, and expect the verb to refuse a sweep whose walls sample to one grid (gotcha #16).** ⛔ **Never compare a single-density `C` across geometries: the SAME cube's single-density `C` wanders with the step across the full width of the «cube↔part gap» canon used to call non-physical (`01_01 §5.2`). Compare FITTED pairs or nothing.** (The cube is locked by construction, so part of that wander is plausibly its porosity staircase — not separated from the mesh-stiffness term, and not measured apart.) ⛔ **And this verb does not produce what a physical test returns by default:** ISO 13314's comparable quantity is the **elastic gradient** — the secant of an UNLOAD/RELOAD hysteresis loop between 20 % and 70 % of plateau stress — never the quasi-elastic gradient, whose role in the standard is to locate the strain zero; so a printed-specimen order without an unloading cycle comes back with nothing to compare against, and any comparison must name a POINT on the curve. ⊕ **Print thickening is a SENSITIVITY, never a body: `fea <cem> --dilate downskin|iso`** — the offset is a FACE displacement (segment LENGTH along +BD in the part frame · ball RADIUS, so a ligament gains 2R); a shifted sample takes metal only from inside the part body while the origin is never clipped, which is what lets the zero row reproduce the pinned `/12` row bit for bit; caches are `dilation_sensitivity.*`, one file per row. Numbers, the literature check and the declared ceiling → `01_01 §5.2`; the table is machine-held by `ruby scripts/fea_canon_sync.rb` (HARD in `docs.yml`; which layer holds which table → read the script itself, never a number here).
- **Check resolution adequacy** — every declared thickness/gap against the voxel its own assembly asks for, `2·voxel` represented / `4·voxel` volume-honest. Hard carrier `ResolutionTests`, operator line inside `verify`. 🔑 Walks the PARSED RECORD TREE: a composite manifest declares a handful of numbers and inherits dozens of `Cem.cs` defaults written for a PART voxel — that inheritance is the defect class, not a detail.
- **Local-verify** (`export PATH="$HOME/.dotnet:$PATH"` first — the SDK is NOT on PATH, so «dotnet is not installed» is never a finding without it): `dotnet build SilkenCad.sln` (0W/0E) → `dotnet run --project src/SilkenCad
  -- verify cem/<x>.json` (metrics.json + exit 0/1) → `dotnet run -- draw cem/<x>.json` (SVG+DXF → out/) → `dotnet run -- fea cem/<x>.json --sweep` (pure-managed like `draw`; ⚠️ it writes into the COMMITTED `cache/fea/`, unlike `out/`, so a run has a diff)
  → `dotnet test`. CI = enterprise 2-job `cad_smoke.yml` (logic = Linux pure-xUnit hard [incl. draw/DXF]
  + render = macOS build-hard + verify best-effort, Library.Go 139 headless — gotcha #3).
  🔴 **`dotnet run` builds DEBUG by default, and for an FE run that is a ×4.1 tax — measured, not assumed** (on the pinned `.d7` part fit: **73 s at `-c Release` against 298 s in Debug**, same machine). ⛔ The reason it is safe to take: the Release run reproduces the committed cache **bit for bit** on every axial cell and on `C`/`n`, so the config is a cost axis and not a numeric one. 🔑 **Where it actually bites is the ESTIMATE, not the run: a cost quoted from a probe carries the probe's BUILD CONFIG inside it, invisibly — when you price a long run from a short one, say which config you measured.** Measured prices, Release: a part `.d7`/`.d10` fit takes minutes, the `.d32` fit 8 h 20 m. ⊕ For a run of hours: `nohup caffeinate -i` (a sleeping Mac stops it), and run the binary from a COPY (`cp -R src/SilkenCad/bin/Release/net9.0/. out/<name>_bin/`) — a parallel agent's `dotnet build` in this tree would otherwise swap the DLLs under a live process. The cache is written only at the END; the per-wall rows print as they solve, so redirect stdout to a durable log or a crash at hour six leaves nothing.
- **Update a submodule**: `git -C tools/cad/extern/<repo> pull` + re-pin the gitlink (vendored LEAP source, kept out of owned code).
