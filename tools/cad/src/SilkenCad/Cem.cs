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

// Flat in-vitro coupon (10x10 mm Ti-monet, 01_01 §6.1) with a suspension eyelet.
internal sealed record TiCoinCem
{
    public string Kind { get; init; } = "ti_coin";
    public string Name { get; init; } = "ti_coin";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float DiscDiameterMm { get; init; } = 10f;
    public float DiscThicknessMm { get; init; } = 1f;
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
