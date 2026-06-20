using System.Numerics;
using System.Text.Json;
using PicoGK;

namespace SilkenCad;

// Golden-metrics: derived geometry measurements, asserted against the CEM spec —
// the .NET peer of the firmware golden-vectors and tools/ml parity gates. Parity is
// on THESE metrics (stable), never the raw STL bytes (voxel-/platform-dependent).
// Embodies Noyron's design↔simulation convergence: the generator emits its own
// predicted physical properties alongside the geometry.
internal sealed record GeometryMetrics
{
    public required string Name { get; init; }
    public required float VoxelSizeMm { get; init; }
    public required double SolidVolumeMm3 { get; init; }
    public required double[] BboxSizeMm { get; init; }
    public required int TriangleCount { get; init; }
    public double? Porosity { get; init; }   // null when no envelope is supplied (solid parts)
}

internal static class Validation
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
    };

    // `envelope` = the solid bounding object (e.g. the un-gyroided pipe) used to
    // turn a raw solid volume into porosity = 1 - V_solid / V_envelope.
    public static GeometryMetrics Measure(string strName, float fVoxelSizeMm, Voxels voxSolid, Voxels? voxEnvelope = null)
    {
        voxSolid.CalculateProperties(out float fVol, out BBox3 bbox);
        Vector3 vecSize = bbox.vecSize();

        double? dPorosity = null;
        if (voxEnvelope is not null)
        {
            voxEnvelope.CalculateProperties(out float fEnv, out BBox3 _);
            if (fEnv > 0f)
                dPorosity = 1.0 - (double)fVol / fEnv;
        }

        return new GeometryMetrics
        {
            Name = strName,
            VoxelSizeMm = fVoxelSizeMm,
            SolidVolumeMm3 = fVol,
            BboxSizeMm = [vecSize.X, vecSize.Y, vecSize.Z],
            TriangleCount = voxSolid.mshAsMesh().nTriangleCount(),
            Porosity = dPorosity,
        };
    }

    public static void WriteJson(GeometryMetrics oMetrics, string strPath)
        => File.WriteAllText(strPath, JsonSerializer.Serialize(oMetrics, Json));
}
