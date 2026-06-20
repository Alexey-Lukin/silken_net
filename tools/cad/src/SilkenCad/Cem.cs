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

// Zone-1 gyroid anode (01_01 §5): a radial-gyroid Ti rod with a central bore for the
// bus conductor. Ø = founder 2026-06-20 (Ø11, HW.33). v1 = CONSTANT radial gyroid;
// the radial pore gradient (300→100µm at constant porosity) is v2 via ImplicitModular.
// Porosity is MEASURED, not assumed — Gibson-Ashby n=2 may overstate gyroid stiffness
// (HW.33), so PorosityTarget is a goal to verify, not a frozen constant.
internal sealed record AnchorCem
{
    public string Kind { get; init; } = "anchor_zone1";
    public string Name { get; init; } = "anchor_zone1";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float OuterDiameterMm { get; init; } = 11f;    // founder 2026-06-20 (HW.33)
    public float BoreDiameterMm { get; init; } = 1.6f;    // central bus conductor (~1–2 mm²)
    public float LengthMm { get; init; } = 40f;           // Zone-1 30–50 mm
    public float GyroidPeriodMm { get; init; } = 2.5f;     // cartesian gyroid period (mm)
    public float GyroidWallParam { get; init; } = 1.0f;    // DIMENSIONLESS band: solid where |eq| < 0.5*param (eq ∈ [-1.5,1.5], NOT mm)
    public float PorosityTarget { get; init; } = 0.65f;
}
