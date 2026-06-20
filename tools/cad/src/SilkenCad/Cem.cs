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
    public float BoreDiameterMm { get; init; } = 1.6f;     // central bus conductor (~1–2 mm²)
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
