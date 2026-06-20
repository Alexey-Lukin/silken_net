# Engineering Drawings from the CEM — Research & Program (anchor + Ti-coin)

> **Status:** research + analysis (2026-06-20, autonomous night session). A *plan*, not yet
> shipped code. Question from founder: «як отримати креслення анкера + Ti-coin у висновку».
> This doc is that висновок: the recommended path, why, and a roadmap. Canon refs are pointers,
> not restated. Decisions that need the founder are collected in §8.

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
3. **Publication / defensive-publication figure** (`08_01 §2`, IP posture = publish-to-protect).
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

- **Deterministic & Git-friendly:** `cem/*.json` + a small drawing generator → a **`.svg`/`.pdf`**
  (text-reviewable, version-controlled, regenerates on a dim change — like `metrics.json`).
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

- **A — C# SVG generator inside `tools/cad` (PRIMARY, recommended PoC).** A new `Drawing.cs` +
  `draw <cem>` verb: compute view rectangles/circles/section-lines from the CEM, emit SVG with
  dimension lines, a title block, GD&T datums, and a notes block. Pure-managed (no `Library.Go`
  for analytic parts → runs in CI logic-job; the gyroid cross-section samples the SDF). Zero new
  runtime deps (SVG is text). Fits the lazy-senior ladder: the numbers already exist, we just lay
  them out. **This is the path that matches our pipeline.**
- **B — STL/STEP → FreeCAD TechDraw, headless Python (FALLBACK, only if the shop demands STEP +
  a full TechDraw sheet).** `mesh2solid`-style headless FreeCAD. Better: feed FreeCAD **analytic
  primitives** built from the CEM (not the voxel mesh) so the STEP is clean. Heavier (FreeCAD dep,
  Python, separate toolchain) → only when a STEP deliverable is contractually required.
- **C — Manual import into Fusion/SolidWorks (ONE-OFF).** Import STL as reference, draw by hand.
  Acceptable for a single publication figure; not for a maintained, regenerating deliverable.

**Recommendation: A** for the maintained drawings (regenerate on every dim change, like metrics),
with **B** kept as the STEP escape-hatch for a factory that won't accept SVG/PDF + STL.

## 6. What an AM drawing must carry (grounded in our canon)

A useful drawing here is **not** a full geometric dump — it's the **acceptance contract**:

- **Envelope + critical mating dims** with **tolerances**: the press-fit Ø11 bore / Ø15 OD, flange
  Ø25, bayonet. Use the real fits — e.g. **H7/s6** for the Zone-1↔Zone-2 press-fit (ISO 286, tens
  of µm) — exactly the band `AxialStack` flagged as missing in F1 (shank Ø placeholder, HW.8.9).
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

## 7. Roadmap

1. **Ti-coin drawing** (path A) — the simplest part and the most urgent (Stage 2). Proves the
   `Drawing.cs` + `draw` verb + title block + dimension-line primitives. One xUnit on the analytic
   layout (view extents, dim values = CEM).
2. **Simple anchor parts** — Zone-2 sleeve, Деталь 3 flange, Деталь 4 radome (analytic sections).
3. **Title block + GD&T datums + tolerance table** — driven by a `tolerances`/`notes` block added
   to the CEM (so fits like H7/s6 are SSOT, feeding both the drawing and HW.8.9 reconcile).
4. **Zone-1 envelope + cross-section + lattice spec** — SDF-sampled section; the AM-correct way.
5. **Assembly drawings** — capsule-end (`Assembly`) + axial stack (`AxialStack`): the mate-audits,
   drawn, with the datum chain and the F1/F2 findings annotated.

## 8. Open questions for the founder (decide before building)

1. **Deliverable format the SLM/PEEK shop will accept** — SVG/PDF drawing + STL enough, or is a
   **STEP** file contractually required? (Decides whether we need path B at all.)
2. **Drawing standard** — ISO 128 (European, first-angle) vs ASME Y14.5 (third-angle)? Ukrainian
   shops typically ISO/ГОСТ → first-angle is the likely default unless a grant/partner says otherwise.
3. **Tolerance source** — fits (H7/s6 etc.) are currently implicit; should they become a **CEM
   `tolerances` block** (SSOT, feeds drawing + HW.8.9) — recommended — or live only on the drawing?
4. **Title-block fields** — company/author/approver, license stamp, the git-SHA-as-revision idea OK?

---

## References

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
