# Engineering Drawings from the CEM — Research & Program (anchor + Ti-coin)

> **Status:** research + program (2026-06-20 analysis; **2026-06-21 decided + web-grounded**). The
> recommended path, why, and a **phased** roadmap (§7). Founder decisions (§8) are **resolved** —
> DXF (netDxf) + SVG · ISO 1st-angle + ISO 1101 · CEM-`tolerances` SSOT; Phase 0+1 active, Phase 2
> deferred. Canon refs are pointers, not restated.
> Question from founder: «як отримати креслення анкера + Ti-coin у висновку».

---

## 1. The need — what a "drawing" is *for* here

Our pipeline today emits **3D geometry** (`build` → STL) + **golden metrics** (`verify` →
`metrics.json`). Neither is a **dimensioned engineering drawing** — the 2D, toleranced,
title-blocked document a human or a shop reads. We need one as a deliverable in four contexts:

1. **Factory handoff (the real driver).** `00_07 HW.1` / `HW.24` say "STL/STEP → SLM завод"; an
   SLM/DMLS shop prints from the **mesh/STEP**, but it inspects and accepts against a **drawing**
   (critical dims, tolerances, datums, post-process notes). Ti-coin (Stage 2, ~15 pcs, `01_01 §6.1`)
   is the **first** physical part → its drawing is the most urgent.
2. **Inspection / acceptance.** AM GD&T is verified by CMM / optical scan vs a GD&T model
   (laser-triangulation / structured-light are the accurate ones for SLM parts). The drawing is
   the reference the scan is compared to. NB: GD&T of **PBF lattices is an open problem** —
   limited industrial knowledge — so a gyroid is **not** drawn point-by-point (see §4).
3. **Publication / defensive-publication figure** (`00_01 §8`, IP posture = publish-to-protect).
4. **Self-review** — a dimensioned 2D view is a different error-surface than a 3D render; it
   catches drift the renderer hides (this is exactly how `AxialStack` found F1).

## 2. Why mesh → STEP → drawing is the WRONG default

The obvious path (STL → STEP → FreeCAD/CAD → 2D drawing) is **lossy and manual** for us:

- STL/voxels are a **mesh**; "Create shape from mesh" + sewing in FreeCAD yields a tessellated
  solid, **not** a parametric one → "won't be as precise as parts made as solids; manual / hybrid
  remodeling is required for tight tolerances" (holocreators, GrabCAD, mesh2solid). For a
  **voxel gyroid** at 0.1 mm this is millions of facets and no clean analytic faces to dimension.
- It **throws away what we already have**: the CEM **knows every dimension exactly** (Ø11, Ø15,
  50 mm, Ø25, shank, bore…) as source-of-truth numbers. Round-tripping them through a mesh and
  back loses precision and provenance — the opposite of the SSOT discipline.
- It needs a **GUI + manual labour** per revision → not Git-diffable, not deterministic, drifts.

**Conclusion:** do not derive the drawing from the mesh. Derive it from the **CEM**, the same way
`metrics.json` is derived — the drawing becomes another **generator output** (the Noyron way:
the generator emits its own predicted properties *and* its own documentation).

## 3. Recommended approach — CEM-native generated drawings

A drawing is just **orthographic views + dimensions + a title block**, and for our parts the views
are computed **analytically from the CEM parameters** we already own — no mesh, no GUI, no loss.

- **Deterministic & Git-friendly:** `cem/*.json` + a small drawing generator → a **`.svg`**
  (text-reviewable, version-controlled, regenerates on a dim change — like `metrics.json`).
  ⚠️ *PDF was scoped here in the 2026-06-20 research and never built* — `draw` emits `.svg` + `.dxf`
  only (`Program.cs`). Convert SVG→PDF ad-hoc if a publication needs it; do not cite PDF as shipped.
- **Exact:** dimension values come straight from the frozen CEM (`01_01 §1`), not a measured mesh.
- **Honest about the lattice:** the gyroid is documented as a **spec callout** (porosity / period /
  topology) on an **envelope** view, not drawn cell-by-cell — which is the AM-industry norm
  (ISO/ASTM 52900: lattices live in the AM file format as spec/metadata, inspected by Archimedes /
  µCT, not by 2D geometry). This matches "GD&T for PBF lattices is limited" — don't over-draw it.

## 4. Per-part strategy

| Part | View strategy | Notes |
|------|---------------|-------|
| **Ti-coin** (Деталь, Stage 2) | Front (Ø16 circle) + side (16×1 rect) + eyelet detail | Trivial analytic; **do FIRST** (most urgent physical part). Active-area Ø + "1 face ≈ 2 cm²" callout (`01_03 §3.5`). |
| **Zone-2 sleeve** (Деталь 2) | Side section (bore Ø11 / OD Ø15 / 50 mm) + end view | Plain tube — fully analytic from CEM. Note hex + flange-shoulder are deferred (`01_01 §Zone 2`). |
| **Деталь 3 flange** | Front (Ø25 + 3 lugs) + side section (shank, bore, O-ring groove) | Analytic; lugs at 120° (asymmetric bbox, as in `verify`). |
| **Деталь 4 radome** | Side section (dome + bell + cavity + socket) + bottom (socket) | Analytic revolved + bell radius callout (≥3/R≥5, `01_04 §5.5`). |
| **Zone-1 anode (gyroid)** | **Envelope** (Ø11 × L40) + **one cross-section** (SDF sample) + **spec callout** | Lattice NOT drawn point-by-point. Cross-section via `fSignedDistance` sampled on a plane → contour (PicoGK has the SDF; no native drawing export, but `voxExtrudeZSlice` + `GenericContour` exist). Spec: porosity 65 %±2, period, topology, "inspect Archimedes/µCT" (`01_01 §5.5`). |
| **Axial stack / capsule-end** | **Assembly drawing** — section through the stacked zones | Reuse `AxialStack.Build` Z-layout; show press-fit interfaces + the F1 gap + datum chain. The audit, drawn. |

## 5. Technical paths (ranked)

- **A — C# generator inside `tools/cad` (PRIMARY, decided).** `Drawing.cs` + `draw <cem>` verb:
  compute view rectangles/circles/section-lines from the CEM, emit **DXF (factory) + SVG (human)**
  with dimension lines, a title block, GD&T datums, and a notes block. **DXF via `netDxf` (MIT, NuGet,
  .NET) — CAD-native, the shop opens it in AutoCAD/Fusion; native dimension entities (linear/radial/
  diametric) → the library draws them, not us** (lazy-senior ladder: a maintained library beats a
  hand-rolled SVG dimension-engine). SVG stays for human/publication/self-review. Pure-managed
  (no `Library.Go` for analytic parts → CI logic-job; gyroid cross-section = pure SDF-sample à la
  `Connectivity.SampleAnchor`, no render). **This is the path that matches our pipeline.**
- **B — STL/STEP → FreeCAD TechDraw, headless Python (FALLBACK, only if a shop contractually demands
  STEP).** Feed FreeCAD **analytic primitives** from the CEM (not the voxel mesh) so the STEP is clean.
  Heavier (FreeCAD dep, Python, separate toolchain). **No light C# path:** `IxMilia.Step` emits only
  basic curves (no B-rep/AP242/PMI), and STEP from our voxel mesh = tessellation-loss = no better than
  STL → STEP is **deferred**, not a blocker (AM shops print from STL/3D; the 2D drawing is for GD&T/CMM
  acceptance, not the print).
- **C — Manual import into Fusion/SolidWorks (ONE-OFF).** Import STL as reference, draw by hand.
  Acceptable for a single publication figure; not for a maintained, regenerating deliverable.

**Decided: A** (DXF via netDxf + SVG) for the maintained drawings — regenerate on every dim change,
like `metrics.json`. **B** (FreeCAD STEP) deferred until a factory contractually requires STEP.

## 6. What an AM drawing must carry (grounded in our canon)

A useful drawing here is **not** a full geometric dump — it's the **acceptance contract**:

- **Envelope + critical mating dims** with **tolerances**: the press-fit Ø11 bore / Ø15 OD, flange
  Ø25, bayonet. ⚠️ **`H7/s6` is the ISO 286 _metal_ hole/shaft table; our press-fits are a Ti shaft
  in a _PEEK_ bore (E≈4 vs Ti≈114 GPa)** → the same geometric interference gives a different contact
  pressure. The CEM carries the **Lamé-computed µm** (`01_01 §4.2`, script 50, E_PEEK-aware), with
  `H7/s6` only as the nominal class label — not a blind ISO-286 lookup. This is the band `AxialStack`
  flagged as missing in F1 (shank Ø placeholder, HW.8.9).
- **GD&T datums** on mating features (bore axis, flange face, bayonet) — concentricity/runout matter
  for the coaxial stack; lattice bulk does not get GD&T.
- **Post-process notes** (the AM-specific half the shop needs): HIP (`01_02 §1.7` / HW.23),
  EAAE + **dehydrogenation bake** (`01_02 §1.3`, HW.27), selective Hard-Gold ENIG map (`02_02 §1.2`,
  HW.8.2), build orientation (`01_02 §1.6`). These belong in the drawing's notes block.
- **Lattice spec callout** (not geometry): porosity 65 %±2, pore period, topology (sheet/network
  open, HW.33), "inspect by Archimedes + µCT" — per ISO/ASTM 52900 lattice-as-spec.
- **Surface finish**: dual-scale roughness Sa (`01_02 §1.2`, HW.2).
- **Title block**: part name + Деталь №, material **Ti-6Al-4V** (PEEK for Zone 2), scale, units
  (mm), revision = git SHA, "geometry SSOT = `cem/<x>.json` + STL", license (CERN-OHL-S for hw).

## 7. Roadmap (phased)

> **Phase 0** (canon honesty + CEM `tolerances`/`notes` block) + **Phase 1** (Ti-coin DXF deliverable)
> are active. **Phase 2** (steps 2/4/5) is deferred until a factory contract — full §7 risks being
> "packaging for an imagined factory" (no contract yet). **One Phase-2 part already landed**: Деталь 3
> flange (step 2) ships as `draw cathode_flange` — it rode the Ø25 freeze, not a contract.

1. **Ti-coin drawing** (**Phase 1**) — the simplest + most urgent part (Stage 2, ~15 pcs). Proves
   `Drawing.cs` + `draw` verb + **DXF (netDxf)** + title block + dimension primitives, consuming the
   CEM `tolerances`/`notes` block (zero hardcoded). xUnit (DXF well-formed, dim values = CEM, no NaN).
2. **Simple anchor parts** (**Phase 2**) — Деталь 3 flange **✅ landed** (`Drawing.CathodeFlange` +
   `CathodeFlangeDxf`; **closes the central-pad Ø4-5 / PEEK-ring gap → HW.8**) — residual: it has no
   xUnit yet, while Ti-coin carries five. Still open: Zone-2 sleeve, Деталь 4 radome (analytic sections).
3. **CEM `tolerances`/`notes` block** (**Phase 0**) — fits (Lamé-µm), GD&T datums, surface-finish,
   post-process notes, lattice-spec are SSOT in `cem/*.json`, feeding drawing + HW.8 + HW.8.9.
4. **Zone-1 envelope + lattice spec** (**Phase 2**) — the gyroid is an **inspection-card** (envelope +
   porosity/period/topology + Archimedes/µCT thresholds), NOT point-by-point (ISO/ASTM 52900). A
   cross-section, if wanted, = **pure SDF-sample à la `Connectivity.SampleAnchor`** (no `Library.Go`).
5. **Assembly drawings** (**Phase 2**) — capsule-end (`Assembly`) + axial stack (`AxialStack`): the
   mate-audits drawn, with the datum chain + F1/F2 findings annotated.

## 8. Decided (founder, 2026-06-21)

Derived from the canon shops (Київ **3D Metal Tech** ISO 13485 / Дніпро **ALT Ukraine** / EU backup
hubs — `02_06 §8.1`) + web-grounding (sources below).

1. **Deliverable format** — **DXF (netDxf) + SVG + STL**. No STEP for now: AM shops print from
   STL/3D, and the drawing is for **GD&T/CMM acceptance**, not the print. STEP = deferred path B if a
   shop contractually requires it.
2. **Drawing standard** — **ISO**, made a CEM/config parameter (default). ⚠️ **These are TWO orthogonal
   choices, not one** — the earlier «ISO 128 vs ASME Y14.5 (third-angle)» was a **conflation**:
   - **Projection convention:** 1st-angle (ISO 128-30 / ISO 5456) vs 3rd-angle (**ASME Y14.3**). → **1st-angle**.
   - **GD&T language:** **ISO 1101** vs ASME Y14.5. → **ISO 1101**.

   ASME Y14.5 is a **GD&T standard, _not_ a projection method**. ASME (3rd-angle + Y14.5) stays as the
   non-default parameter value, only if a US partner/grant dictates.
3. **Tolerance source** — **CEM `tolerances` block** (Noyron-native SSOT; feeds drawing + HW.8.9 +
   HW.8 central-pad). Per LEAP 71 Noyron, manufacturing constraints live in the computational model,
   not on a one-off drawing — the drawing/DXF renders them.
4. **Title-block fields** — git-SHA as revision (provenance) + the SSOT pointer (`cem/<x>.json`); add a
   human rev-letter when a shop needs one.

## 9. References

**Decision web-grounding (2026-06-21):**
- ASME Y14.3 (3rd-angle projection) vs ASME Y14.5 (GD&T) vs ISO 128/5456/1101 — the conflation fix:
  gdandtbasics.com, en.wikipedia.org/wiki/ASME_Y14.5, peachpit (ASME Y14.3).
- DXF / `netDxf` (MIT): github.com/haplokuon/netDxf. C# STEP `IxMilia.Step` (insufficient — basic
  curves only): github.com/ixmilia/step. CadQuery/build123d (other-stack 2D export): cadquery.readthedocs.io.
- MBD / STEP AP242 trend: autodesk.com, sigmetrix.com, spatial.com. PEEK press-fit creep / ISO 286
  polymer caveat: janeemachining, trelleborg. Noyron / LEAP 71: leap71.com/noyron, 3dprintingindustry.com.

**Methodology:**
- AM inspection / GD&T: *Optical Inspection Systems for SLM parts* (PMC7308957); *GD&T of AM/PBF
  lattices review* (ResearchGate 360426092) — lattice GD&T is an open problem.
- STL→STEP loss: holocreators STL-to-STEP, GrabCAD FreeCAD tutorial, `Charles-Garrison/mesh2solid`
  (headless FreeCAD) — mesh→solid is lossy, manual rebuild for tolerances.
- Standards: ISO/ASTM 52900:2021 (AM fundamentals; lattice/metadata in the AM file format),
  ISO/ASTM 52902:2023 (test artefacts / geometric capability).
- PicoGK/ShapeKernel surface: `fSignedDistance` (SDF sample → section), `voxExtrudeZSlice`,
  `GenericContour` — no native drawing/SVG/DXF export (→ we generate it).
- Canon: `01_01 §1/§5.5/§6.1` · `01_02 §1.2/§1.3/§1.6/§1.7/§6` · `02_02 §1.2/§4.4/§4.5` ·
  `01_03 §3.5` · `01_04 §5.5` · `00_07 HW.1/HW.2/HW.8/HW.23/HW.24/HW.27/HW.33`.
