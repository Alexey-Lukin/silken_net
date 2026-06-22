using System.Text.Json;

namespace SilkenCad;

// CEM = Computational Engineering Model manifest: the Git-SSOT input that drives a
// generator. The term + spirit are LEAP 71 Noyron's — a CEM is a DETERMINISTIC
// algorithm, not generative ML. Geometry is COMPUTED from these parameters; the
// .json + the .cs generator together are the source of truth, the STL is a derived
// build artifact (gitignored, parity is on cem/*.metrics.json instead).
internal static class Cem
{
    private static readonly JsonSerializerOptions Opts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    // Cheap discriminator read so `build` can dispatch to the right generator.
    public static string Kind(string strJson)
    {
        using JsonDocument doc = JsonDocument.Parse(strJson);
        return doc.RootElement.TryGetProperty("kind", out JsonElement el) && el.GetString() is { } strKind
            ? strKind
            : throw new InvalidDataException("CEM manifest is missing a 'kind' field");
    }

    public static T Parse<T>(string strJson) =>
        JsonSerializer.Deserialize<T>(strJson, Opts)
        ?? throw new InvalidDataException("CEM manifest deserialized to null");
}

// Engineering-drawing PMI (Product Manufacturing Information) — the tolerance + GD&T spec a drawing/DXF
// carries. Per LEAP 71 Noyron, manufacturing constraints live in the CEM (the computational model), NOT
// on a one-off drawing — the `draw` verb just renders them. Optional on every part record (null ⇒ no
// callout). Feeds the factory acceptance contract + the HW.8 / HW.8.9 reconcile.
internal sealed record ToleranceSpec
{
    // Fit / press-fit interference. ⚠ For a Ti shaft in a PEEK bore, `H7/s6` is only the NOMINAL class
    // label — PEEK E≈4 vs Ti≈114 GPa, so the same geometric interference gives a different contact
    // pressure. The REAL band is the Lamé-computed µm (01_01 §4.2, script 50, HW.3.IS), NOT a blind
    // ISO-286 metal-table lookup → put it in InterferenceMin/MaxUm.
    public string? Fit { get; init; }                  // nominal class label, e.g. "H7/s6"
    public float? InterferenceMinUm { get; init; }     // Lamé band (E_PEEK-aware), µm
    public float? InterferenceMaxUm { get; init; }
    public float? ClearanceMm { get; init; }           // hex/spline anti-rotation ≤0.05 (01_01 §4.3 C)

    // Linear ± on a named feature (e.g. "bore", "flange_dia").
    public string? Feature { get; init; }
    public float? PlusMm { get; init; }
    public float? MinusMm { get; init; }

    // GD&T datums + geometric tolerances (ISO 1101 — the coaxial stack needs concentricity/runout on the
    // mating bore/flange; the lattice bulk gets no GD&T).
    public string? PrimaryDatum { get; init; }         // e.g. "bore axis"
    public string? SecondaryDatum { get; init; }       // e.g. "flange face"
    public string? ConcentricityMm { get; init; }      // e.g. "0.05"
    public string? RunoutMm { get; init; }
}

// Engineering-drawing notes — the AM-specific acceptance half (material, process, surface finish,
// post-process, coating restrictions, lattice spec, inspection). Plain canon-sourced text the `draw`
// verb lays into the notes block (replaces the hardcoded Ti-coin lines → Noyron-clean). Optional (null
// fields skipped). Canon: 01_01 §1 + 01_02 §1.
internal sealed record NotesSpec
{
    public string? Material { get; init; }             // "Ti-6Al-4V (Grade 5)" | "PEEK 450G"
    public string? Process { get; init; }              // "SLM+HIP" | "CNC (annealed 200–250 °C)" | "EBM"
    public string? SurfaceFinish { get; init; }        // "micro Sa 0.5–5 µm + nano Sv 50–500 nm (EAAE, 01_02 §1.2)"
    public string? PostProcess { get; init; }          // "HIP (01_02 §1.7) · dehydrogenation bake · build tip-down §1.6"
    public string? CoatingRestriction { get; init; }   // "ZnO-Ta/HAp/RGD FORBIDDEN on Zone-1 gyroid (blocks DET) — 01_02 §3.6"
    public string? LatticeSpec { get; init; }          // "porosity 65±2 % / period … / topology … — inspect Archimedes+µCT (ISO/ASTM 52900)"
    public string? Inspection { get; init; }           // "SEM ×500/5000/50000 · ICP-MS Al<1 ppb (01_02 §1.5)"
    public string[]? Extra { get; init; }              // free lines (Ti-coin active-area, RF keep-out, …)
}

// Flat in-vitro Ti coupon (Stage-2 CV/EIS, 01_01 §6.1). Ø16 disc → 1 face ≈ A_electrode 2 cm²
// (01_03 §3.5). Disc not square: RDE-ready, uniform radial j, no corner edge-effects. j is
// normalised on the PROJECTED geometric area (EAAE roughness makes the true area unmeasurable, 01_02 §1.4).
internal sealed record TiCoinCem
{
    public string Kind { get; init; } = "ti_coin";
    public string Name { get; init; } = "ti_coin";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float DiscDiameterMm { get; init; } = 16f;     // 1 face = π·(D/2)² ≈ A_electrode 2 cm² (01_03 §3.5)
    public float DiscThicknessMm { get; init; } = 1f;
    // A lab O-ring / lacquer window can fix exactly 2 cm² INSIDE a larger coupon — decouples A from the coin
    // edge (same A across drop-cast / masked-window / O-ring cell). 0 ⇒ the whole face is the active area.
    public float ActiveWindowDiameterMm { get; init; }
    public float LoopRingRadiusMm { get; init; } = 1.6f;  // torus centreline radius
    public float LoopTubeRadiusMm { get; init; } = 0.6f;  // torus tube (wire) radius
    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (null ⇒ no callout)
    public NotesSpec? Notes { get; init; }                // drawing notes block (null ⇒ defaults)
}

// Zone-1 gyroid anode (01_01 §5): a cartesian-gyroid Ti rod with a central bore for the
// bus conductor (Ø = founder 2026-06-20, Ø11, HW.33). v2 = radially GRADED gyroid with three
// INDEPENDENT, CEM-driven axes (the FEA/bio "which is best" answer is open, so none is hard-coded):
//   • pore/cell size — GyroidPeriod{Mm core → RimMm} (biology: ingrowth core / transport rim)
//   • porosity / E   — GyroidWallParam{ core → Rim }  (mechanics: HOLD or GRADE the porosity)
//   • topology       — Topology = sheet|network        (surface vs stress-shielding, HW.33)
// Core = axis (r=bore/2), Rim = periphery (r=outer/2); a *Rim* field of 0 ⇒ equals Core ⇒ v1 constant.
// Porosity is MEASURED, never assumed: PorosityTarget is only a verify goal, and 65 % itself is a rough
// placeholder (founder 2026-06-21) — Gibson-Ashby n=2 suits network, not our sheet (n≈1.3 → higher E),
// and wood E is anisotropic (HW.33). Porosity is a parameter here, not a frozen truth.
internal sealed record AnchorCem
{
    public string Kind { get; init; } = "anchor_zone1";
    public string Name { get; init; } = "anchor_zone1";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float OuterDiameterMm { get; init; } = 11f;     // founder 2026-06-20 (HW.33)
    public float BoreDiameterMm { get; init; } = 1.6f;     // legacy hollow bus channel (gyroid inner); superseded by the monolithic rod below when >0
    public float BusRodDiameterMm { get; init; }           // monolithic SOLID bus rod Ø (01_01 §1.4): >0 ⇒ rod core + gyroid annulus; 0 ⇒ legacy hollow bore
    public float LengthMm { get; init; } = 40f;            // Zone-1 30–50 mm

    // Cell-size (pore) axis — period at the core; RimMm tapers it toward the periphery.
    public float GyroidPeriodMm { get; init; } = 2.5f;     // core period (mm); printable wall ≈ 0.1·period
    public float GyroidPeriodRimMm { get; init; }          // periphery period (mm); 0 ⇒ = core (constant size)

    // Porosity axis — dimensionless band (solid where |eq| < 0.5·param, eq ∈ [-1.5,1.5], NOT mm).
    public float GyroidWallParam { get; init; } = 1.0f;    // core band
    public float GyroidWallParamRim { get; init; }         // periphery band; 0 ⇒ = core (constant porosity)

    // sheet (more surface, stiffer) | network (lower-E) | stepped (heterostructure zones: strong pore
    // contrast at constant porosity — uses Period + PeriodRim as the two zone periods, ignores wall-grad)
    public string Topology { get; init; } = "sheet";
    public float PorosityTarget { get; init; } = 0.65f;    // verify goal only — placeholder, FEA-gated (HW.33)
}

// Mechanical-lock shank (01_01 §4.3 A/B) — the §4.3 BLOCKER-3 lock against PEEK cold-flow creep
// (HW.26): annular ratchet barbs + a DIN-471 retaining groove on the solid Ti shank that press-fits
// into the PEEK sleeve. A self-contained demo part (Zone 1 real Ø11, Zone 3 placeholder Ø) — NOT yet
// integrated into the gyroid rod (separate session, 00_07). Canon over-specifies the tooth (h, base,
// α, β all fixed); a triangle has 2 free params, so we keep α/β + h and DERIVE base ≈ 2.1·h — verify
// MEASURES it against §4.3 [0.40,0.60]. Barbs emit GEOMETRY only: the 3–5× pull-out, the PEEK 150 °C
// click and friction retention are FEA (Гусак, HW.3.IS) + bench, never asserted here.
internal sealed record MechanicalLockCem
{
    public string Kind { get; init; } = "mechanical_lock";
    public string Name { get; init; } = "mechanical_lock";
    public float VoxelSizeMm { get; init; } = 0.05f;       // barb-feature floor (h≈0.28 → ~6 voxels); exact tip = µCT (01_01 §5.6)
    public float ShankDiameterMm { get; init; } = 11f;     // Zone-1 anode Ø (founder, HW.33); Zone-3 = PLACEHOLDER (HW.8 dim-freeze)
    public float ShankLengthMm { get; init; } = 18f;
    public float BoreDiameterMm { get; init; } = 1.3f;     // central bus-conductor channel (§1 — the shank is hollow); 0 ⇒ solid
    public float ContactStartMm { get; init; } = 2f;       // z where PEEK contact begins
    public float ContactLengthMm { get; init; } = 12f;     // contact zone 8–15 mm (§4.3 A)

    // Ratchet tooth — keep α/β + h, base is DERIVED = h·(cot α + cot β); MEASURED in verify.
    public int BarbRows { get; init; } = 4;                // 3–5 rows (§4.3 A)
    public float BarbHeightMm { get; init; } = 0.28f;      // h 0.25–0.40; base≈0.59 ∈ [0.40,0.60] at α30/β70
    public float LeadAngleDeg { get; init; } = 30f;        // α leading — shallow ⇒ long ramp ⇒ easy hot insert
    public float TrailAngleDeg { get; init; } = 70f;       // β trailing — steep ⇒ short ramp ⇒ hard pull-out
    public int BarbDirection { get; init; } = 1;           // +1 Zone-1 lean; −1 Zone-3 opposite (§4.3 figure)

    // DIN-471 retaining-ring groove (§4.3 B) — ∅0.8 × 0.6 deep, near the outer (capsule-side) end.
    public float GrooveOffsetMm { get; init; } = 15f;
    public float GrooveWidthMm { get; init; } = 0.8f;
    public float GrooveDepthMm { get; init; } = 0.6f;
}

// Zone 3 cathode flange (Деталь 3, 01_01 §1 + 02_02 §1.2) — the capsule-side anchor end: a SOLID Ti
// flange (Ø25 frozen) on a barbed shank that press-fits into the PEEK Zone-2 sleeve. Top face = pogo-pad
// plane (centre GND bus + outer V+, Hard Gold — coating, NOT geometry); the side/perimeter is the cathode
// catalytic zone (Laccase/ZIF + PTFE-GDL, O₂ from the side under the radome bell — 02_02 §1.2, фаза-2).
// Bayonet lugs mate the PEEK Radome (Деталь 4). Barbs reuse the §4.3 lock (Zone-3 set, opposite lean).
// Shank Ø + flange thickness = HW.8 placeholders (no-premature-canon).
internal sealed record CathodeFlangeCem
{
    public string Kind { get; init; } = "cathode_flange";
    public string Name { get; init; } = "cathode_flange";
    public float VoxelSizeMm { get; init; } = 0.05f;       // barb-feature floor (as mechanical_lock)
    public float FlangeDiameterMm { get; init; } = 25f;    // frozen (01_01 §1 = Radome Ø, 02_02 §1.3)
    public float FlangeThicknessMm { get; init; } = 3f;    // placeholder (HW.8 dim-freeze)
    public float ShankDiameterMm { get; init; } = 9f;      // placeholder (HW.8); Zone-3 into PEEK
    public float ShankLengthMm { get; init; } = 14f;
    public float BoreDiameterMm { get; init; } = 1.3f;     // GND bus channel (hollow through flange+shank) — the monolithic rod threads it, isolated
    public float BusLinerThicknessMm { get; init; }        // bus-rod insulation liner in the channel (01_01 §1.4); feeds the F3 BusRodClears clearance

    // Barbs (§4.3, reuse MechanicalLock; Zone-3 = opposite ratchet lean, dir −1)
    public int BarbRows { get; init; } = 3;
    public float BarbHeightMm { get; init; } = 0.28f;
    public float LeadAngleDeg { get; init; } = 30f;
    public float TrailAngleDeg { get; init; } = 70f;
    public float ContactStartMm { get; init; } = 2f;
    public float ContactLengthMm { get; init; } = 9f;
    public float GrooveOffsetMm { get; init; } = 12f;      // DIN-471 for an Ø9 shaft
    public float GrooveWidthMm { get; init; } = 1.0f;
    public float GrooveDepthMm { get; init; } = 0.3f;

    // Bayonet lugs (mate the Радом socket, фаза 2) — radial pins evenly spaced
    public int BayonetLugs { get; init; } = 3;
    public float LugProtrusionMm { get; init; } = 2f;      // radial protrusion beyond the flange rim
    public float LugRadiusMm { get; init; } = 1.5f;        // pin radius

    // O-ring groove on the flange underside (mate the Радом O-ring, CS 1.78 → 02_02 §3.2)
    public float ORingGrooveDepthMm { get; init; } = 0.9f;
    public float ORingGrooveWidthMm { get; init; } = 2.0f;

    // Pogo-pad features (02_02 §1.2) — the central GND bus pad (Hard Gold ENIG = the Ti↔Au galvanic-trap
    // fix) + the PEEK isolation ring guarding the centre↔outer short. Ø = HW.8 placeholders (canon says
    // «точні Ø фланця/площадки потребують CAD → HW.8»; the flange drawing is that forcing function, §F).
    public float CentralPadDiameterMm { get; init; } = 4.5f;   // GND bus-exit pad, Hard Gold ENIG (4–5, HW.8)
    public float IsolationRingWidthMm { get; init; } = 1.5f;   // PEEK ring centre↔outer (≥1.5, short-circuit guard)

    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (concentricity — coaxial stack)
    public NotesSpec? Notes { get; init; }                // drawing notes block
}

// PEEK Radome (Деталь 4, 02_01 §5.2 + 01_04 §5.5) — the radio-transparent dome that bayonets onto the
// Zone-3 cathode flange (Деталь 3) and caps the PCB. A HOLLOW PEEK shell (Ø25): a rounded shield bell
// (≥3 mm over bark, R≥5 — anti-overgrowth, no callus-grip edge) + an internal PCB cavity (antenna↔Ti
// ≥12 mm) + a bayonet socket (L-slot mating the Деталь-3 lugs) + a rim O-ring groove. The cathode is NOT
// sealed under the dome — it breathes O₂ from the SIDE/perimeter (02_02 §1.2; gas-phase 5–10× vs dissolved).
internal sealed record RadomeCem
{
    public string Kind { get; init; } = "radome";
    public string Name { get; init; } = "radome";
    public float VoxelSizeMm { get; init; } = 0.1f;        // dome ~Ø25, no sub-mm features → 0.1 ok
    public float DomeDiameterMm { get; init; } = 25f;      // frozen (= Zone-3 flange Ø, 02_02 §1.3)
    public float WallThicknessMm { get; init; } = 2f;      // 1.5–2.0 (RF vs strength, 02_01 §5.2)
    public float CavityHeightMm { get; init; } = 13f;      // PCB stack (Power+B2B+RF); antenna↔Ti ≥12
    public float BellRiseMm { get; init; } = 3f;           // rounded top over the body (≥3, 01_04 §5.5)
    public float BellRadiusMm { get; init; } = 5f;         // top edge round (≥5 — no callus-grip edge)

    // Bayonet socket (mate Деталь-3 lugs) — L-slot: 3 axial entry slots + a circumferential lock groove
    public int BayonetLugs { get; init; } = 3;
    public float LugRadiusMm { get; init; } = 1.5f;        // = Деталь-3 lug radius (mate-fit)
    public float SlotClearanceMm { get; init; } = 0.3f;    // socket slot clearance over the lug
    public float LockGrooveZMm { get; init; } = 3.5f;      // z of the circumferential lock groove from the rim

    // O-ring groove on the rim (mate the Деталь-3 O-ring, CS 1.78 → 02_02 §3.2); width ≤ wall (fits the 2 mm wall)
    public float ORingGrooveDepthMm { get; init; } = 0.9f;
    public float ORingGrooveWidthMm { get; init; } = 1.0f;
}

// Zone 2 PEEK thermal-break sleeve (Деталь 2, 01_01 §1 + §4.1/§4.2) — the MIDDLE part: a plain hollow
// PEEK tube that press-fits onto the Zone-1 anode shaft (one end) and receives the Zone-3 flange shank
// (the other end), thermally decoupling the buried anode from the capsule-side cathode. Frozen dims
// (01_01 §1): bore Ø11 (= Zone-1 shaft, press-fit H7/s6), wall 2.0 mm (CTE-limited Lamé SF 3.7×, NOT
// press-fit hoop — §4.2), OD Ø15 = the WOUND in the tree (CODIT <25 → DBH ≥38). Length 50 mm (axial
// thermal break, §4.1). The bore is a plain round hole: anti-rotation is a hex/spline profile in canon
// (§1 + §4.3 C, ≤0.05 mm clearance) but that is bench-gated and not needed for the mate-audit → deferred
// (00_07). DIN-471 retaining grooves live on the Ti Zone-1/Zone-3 ends (§3 step 6), NOT the PEEK sleeve;
// barbs are pressed INTO the bore by the Ti shanks at 150 °C (§3 steps 4–5) → the PEEK bore is smooth
// here. The bus conductor runs inside the ANODE's own Ø1.6 bore, not the sleeve (the bore holds the shaft).
internal sealed record Zone2SleeveCem
{
    public string Kind { get; init; } = "zone2_sleeve";
    public string Name { get; init; } = "zone2_sleeve";
    public float VoxelSizeMm { get; init; } = 0.1f;       // no sub-mm features (a plain tube) → 0.1 ok (as radome)
    public float BoreDiameterMm { get; init; } = 11f;     // = Zone-1 anode Ø (press-fit), frozen 01_01 §1
    public float WallThicknessMm { get; init; } = 2f;     // CTE Lamé SF 3.7× (§4.2), frozen — NOT press-fit hoop
    public float LengthMm { get; init; } = 50f;           // axial thermal break (§4.1), frozen
    // OD = bore + 2·wall = Ø15 = the wound diameter in the tree (derived in Zone2Sleeve.OuterR, not stored).
    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (press-fit Lamé-µm, hex clearance)
    public NotesSpec? Notes { get; init; }                // drawing notes block
}

// Capsule-end anchor ASSEMBLY (Деталь 3 ↔ Деталь 4, 02_02 §4 — Механізм Фіксації Капсули). The first
// INTEGRATION artifact: the per-part generators are each verified in isolation, but nothing yet proves
// they MATE. This CEM drives `Assembly` to bring the cathode flange and the PEEK radome into one
// coordinate frame at the bayonet-closed datum (radome lock-groove aligned to the flange lugs) and
// MEASURE the residual mismatch — a failed verify with concrete numbers is the valuable result (HW.17).
// Reuses the Деталь-3 / Деталь-4 records wholesale (nested), so the assembly inherits their frozen dims
// and a CEM may override a sub-field or keep the defaults. Z-stack inputs come from the in-silico
// 1-D tolerance chain (`tools/in_silico/scripts/52_z_stack_tolerance.py`) — the geometry mirror of it.
internal sealed record AnchorAssemblyCem
{
    public string Kind { get; init; } = "anchor_assembly";
    public string Name { get; init; } = "anchor_assembly";
    public float VoxelSizeMm { get; init; } = 0.15f;   // assembly-scale (Ø~30 × ~38 mm) — disc/wall/lug interference, not barbs

    // MATE-Ø candidate (HW.17): asis = baseline (surfaces the conflict) · skirt = radome enclosing skirt to
    // Ø(lug-tip + clearance) · inboard = flange lugs kept within Ø25 (protrusion clamped). asis is the audit.
    public string MateStrategy { get; init; } = "asis";

    // Z-stack inputs (script 52): O-ring rim↔Zone3 gap target + RF antenna↔Ti floor (02_01 §5.3).
    public float ORingGapMm { get; init; } = 1.424f;      // GAP_OR = ORING_CS(1.78)·(1−0.20), script 52
    public float RfClearanceMinMm { get; init; } = 12f;   // antenna↔Ti min Z for VSWR (02_01 §5.3)
    public float SkirtClearanceMm { get; init; } = 0.5f;  // skirt OD = lug-tip Ø + 2·clearance

    // Components — reuse the per-part records (nested); defaults = the frozen Деталь-3 / Деталь-4 dims.
    public CathodeFlangeCem Flange { get; init; } = new();
    public RadomeCem Radome { get; init; } = new();
}

// Full anchor AXIAL stack (Zone 1 anode → Zone 2 PEEK sleeve → Zone 3 flange → Zone 4 radome, 01_01
// §1 + §3). The SECOND integration artifact (after the capsule-end Assembly): it brings the WHOLE
// anchor into one frame along its axis and MEASURES the PRESS-FIT interfaces no prior part ever proved
// mate — Zone-1↔Zone-2 and Zone-2↔Zone-3. Like Assembly it is an AUDIT table, not a part pass/fail:
// the press-fit findings are the real un-reconciled state (HW.8), surfaced as ⚠ + asserted by the pure
// xUnit suite. Reuses the per-part records wholesale (nested) — Zone1 (AnchorCem) + Zone2 (Zone2SleeveCem)
// + the existing capsule-end Assembly (AnchorAssemblyCem = flange+radome) — so it inherits every frozen
// dim and the bayonet (Zone-3↔Zone-4) audit comes for free. Render uses the Zone-1 ENVELOPE (a solid
// Ø11 rod), not the gyroid: a press-fit cares about the OD, not the internal porosity (that lives in
// anchor_zone1 @0.1) — and it keeps the stack-scale 0.2 mm voxel safe (a ~0.25 mm gyroid wall would
// fragment at 0.2). Z-datum = tree-side at z=0 (anode bottom) → capsule-side up.
internal sealed record AnchorAxialStackCem
{
    public string Kind { get; init; } = "anchor_axial_stack";
    public string Name { get; init; } = "anchor_axial_stack";
    public float VoxelSizeMm { get; init; } = 0.2f;     // stack-scale (Ø15 × ~100 mm) — measures fit/interference, not porosity

    // How deep the Zone-1 anode shaft inserts into the Zone-2 bore (press-fit overlap). The Zone-3 shank
    // enters the OTHER end by its own shank length → InsertionBudget guards the two shanks don't collide.
    public float Zone1InsertionMm { get; init; } = 30f;

    // Components — reuse the per-part records (nested); defaults = the frozen Zone-1 / Zone-2 dims + the
    // capsule-end (flange + radome) sub-assembly (it carries its own mate strategy).
    public AnchorCem Zone1 { get; init; } = new();
    public Zone2SleeveCem Zone2 { get; init; } = new();
    public AnchorAssemblyCem Capsule { get; init; } = new();
}
