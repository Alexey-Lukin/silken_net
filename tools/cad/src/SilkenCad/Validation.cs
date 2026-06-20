using System.Numerics;
using System.Text.Json;
using PicoGK;
using Leap71.ShapeKernel;

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
    public double? Porosity { get; init; }                  // null when no envelope is supplied (solid parts)

    // v2 graded-anchor measurements (null for non-anchor parts):
    public double[]? RadialPorosityByShell { get; init; }   // core→rim; ~flat = constant SKU, monotone = graded SKU
    public double? FinestPeriodMm { get; init; }            // smallest cell period across radius (the rim); wall ≈ 0.1× this — the DMLS-floor proxy (exact wall = µCT, 01_01 §5.6)
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

    // Anchor-specific golden metrics: the base measurement + porosity measured per concentric
    // radial shell (proves the porosity PROFILE — flat for a constant SKU, monotone for a graded
    // one) + the finest cell period (DMLS-floor proxy). Porosity is MEASURED, never derived from
    // wallParam (gotcha #4): a coarse voxel under-resolves voids → falsely high porosity.
    public static GeometryMetrics MeasureAnchor(AnchorCem cem, Voxels voxAnode, Voxels voxEnvelope, int nShells = 5)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, voxAnode, voxEnvelope);

        float fRInner = cem.BoreDiameterMm / 2f;
        float fROuter = cem.OuterDiameterMm / 2f;
        float fDr = (fROuter - fRInner) / nShells;

        // Cumulative-diff per shell: a thin ring intersected with distorted (high-gradient) geometry
        // under-counts metal at the voxel edges, so each shell = the DIFFERENCE of two thick bore→r
        // pipes. By construction the outermost cumulative pipe = the full envelope ⇒ the shells always
        // sum back to the global porosity (no thin-ring measurement drift), honest even when distorted.
        double[] aShellPorosity = new double[nShells];
        double dPrevSolid = 0, dPrevEnv = 0;
        for (int i = 0; i < nShells; i++)
        {
            BasePipe oCum = new(new LocalFrame(), cem.LengthMm, fRInner, fRInner + ((i + 1) * fDr));
            Voxels voxCum = oCum.voxConstruct();
            voxCum.CalculateProperties(out float fCumEnv, out BBox3 _);
            voxCum.BoolIntersect(voxAnode);
            voxCum.CalculateProperties(out float fCumSolid, out BBox3 _);
            double dShellEnv = fCumEnv - dPrevEnv;
            double dShellSolid = fCumSolid - dPrevSolid;
            aShellPorosity[i] = dShellEnv > 0 ? 1.0 - (dShellSolid / dShellEnv) : 0.0;
            dPrevSolid = fCumSolid;
            dPrevEnv = fCumEnv;
        }

        float fPeriodRim = cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;

        return oBase with
        {
            RadialPorosityByShell = aShellPorosity,
            FinestPeriodMm = Math.Min(cem.GyroidPeriodMm, fPeriodRim),
        };
    }

    public static void WriteJson(GeometryMetrics oMetrics, string strPath)
        => File.WriteAllText(strPath, JsonSerializer.Serialize(oMetrics, Json));
}
