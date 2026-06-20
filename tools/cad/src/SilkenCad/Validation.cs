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

    // ARCH.25 two-phase connectivity + specific-surface (null for non-anchor parts). See Connectivity.cs
    // for the canon mapping (open-pore↔Archimedes, percolation↔EAAE flow-through, solid-disc↔AM islands).
    public double? OpenPorosity { get; init; }              // pore reachable from a surface / total pore (~1.0 for a sound gyroid)
    public double? ClosedPoreFraction { get; init; }        // trapped voids = 1 − open (~0)
    public double? SolidDisconnectedFraction { get; init; } // metal not in the largest body (floating islands; print + electrical defect, ~0)
    public bool[]? PorePercolates { get; init; }            // [X,Y,Z] spanning (X,Y rim-to-rim radial; Z end-to-end axial)
    public int? PoreClusterCount { get; init; }             // big pore clusters: network→1, sheet→2 (tricontinuous — a fact, not a defect)
    public double? SpecificSurfaceMm2PerMm3 { get; init; }  // wetted area / bbox volume — EBFC-area proxy (sheet ~2× network), HW.33 trade-off
    public double[]? AxialPorosityProfile { get; init; }    // per-Z porosity; must be ~flat (the radial-gradient axial-uniformity gate)

    // Mechanical-lock shank measurements (01_01 §4.3, null for non-lock parts). See Validation.MeasureLock.
    public int? BarbCount { get; init; }                    // ratchet teeth counted along R(z) — must == BarbRows
    public double? MaxBarbHeightMm { get; init; }           // peak ridge height h (§4.3 A: 0.25–0.40)
    public double? BarbBaseMm { get; init; }                // tooth base = h·(cot α + cot β) (§4.3 A: 0.40–0.60)
    public double? GrooveDepthMm { get; init; }             // DIN-471 retaining groove depth (§4.3 B: 0.6)
    public double? SelfSupportFaceDeg { get; init; }        // best-orientation downfacing barb angle from horizontal; ≥45° self-supports (Ti64 LPBF: 60° → Sa≈15µm)
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

        // ARCH.25 two-phase topological audit — sampled from the CEM's own SDF (pure-managed,
        // geometric-intent), independent of the render. Coarser grid (topology is threshold-stable).
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem);
        ConnectivityMetrics conn = Connectivity.Analyse(grid);
        double[] aAxial = Connectivity.AxialProfile(grid);

        // Specific surface (EBFC-area proxy) — REUSE LEAP Measure (wetted mesh area), not own, on the
        // as-rendered anode; normalised by bbox volume so sheet (~2×) vs network is directly comparable.
        float fSurfaceMm2 = Leap71.ShapeKernel.Measure.fGetSurfaceArea(voxAnode);
        double dBboxVol = oBase.BboxSizeMm[0] * oBase.BboxSizeMm[1] * oBase.BboxSizeMm[2];

        return oBase with
        {
            RadialPorosityByShell = aShellPorosity,
            FinestPeriodMm = Math.Min(cem.GyroidPeriodMm, fPeriodRim),
            OpenPorosity = conn.OpenPorosity,
            ClosedPoreFraction = conn.ClosedPoreFraction,
            SolidDisconnectedFraction = conn.SolidDisconnectedFraction,
            PorePercolates = conn.PorePercolates,
            PoreClusterCount = conn.PoreClusterCount,
            SpecificSurfaceMm2PerMm3 = dBboxVol > 0 ? fSurfaceMm2 / dBboxVol : 0.0,
            AxialPorosityProfile = aAxial,
        };
    }

    // Mechanical-lock golden metrics (01_01 §4.3): barb count/height/base + groove depth MEASURED off the
    // R(z) profile (proves the param→geometry math, catches generator bugs), plus a Noyron-style
    // manufacturability field. A vertical build oriented gentle-ramp-DOWN gives a downface of 90−min(α,β)
    // from horizontal; ≥45° self-supports (the steep ramp then faces up). Print orientation ≠ assembly
    // orientation ⇒ this costs no ratchet retention. (Groove = CNC post-DMLS per §4.3 — modelled here only
    // for the as-assembled envelope, not a printed overhang.)
    public static GeometryMetrics MeasureLock(MechanicalLockCem cem, Voxels voxShank)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, voxShank, null);

        var oSdf = new MechanicalLockShank(cem);
        float fRShank = cem.ShankDiameterMm / 2f;
        float fZ0 = cem.ContactStartMm, fZ1 = cem.ContactStartMm + cem.ContactLengthMm;
        const float fDz = 0.005f;

        // Each contiguous run of R(z) > rShank across the contact zone is one tooth → count + base width;
        // the deepest ridge is the peak height.
        int nBarbs = 0;
        double dMaxH = 0;
        var aBaseW = new List<double>();
        bool bInTooth = false;
        double dRunStart = 0, dLastZ = fZ0;
        for (float fZ = fZ0; fZ <= fZ1 + (fDz / 2f); fZ += fDz)
        {
            double dH = oSdf.ProfileRadius(fZ) - fRShank;
            if (dH > dMaxH) dMaxH = dH;
            bool bTooth = dH > 1e-4;
            if (bTooth && !bInTooth) { dRunStart = fZ; bInTooth = true; }
            else if (!bTooth && bInTooth) { aBaseW.Add(dLastZ - dRunStart); nBarbs++; bInTooth = false; }
            dLastZ = fZ;
        }
        if (bInTooth) { aBaseW.Add(dLastZ - dRunStart); nBarbs++; }

        // Groove depth = deepest cut across the groove band.
        double dGrooveMinR = fRShank;
        for (float fZ = cem.GrooveOffsetMm; fZ <= cem.GrooveOffsetMm + cem.GrooveWidthMm; fZ += fDz)
            dGrooveMinR = Math.Min(dGrooveMinR, oSdf.ProfileRadius(fZ));

        return oBase with
        {
            BarbCount = nBarbs,
            MaxBarbHeightMm = dMaxH,
            BarbBaseMm = aBaseW.Count > 0 ? aBaseW.Average() : 0.0,
            GrooveDepthMm = fRShank - dGrooveMinR,
            SelfSupportFaceDeg = 90.0 - Math.Min(cem.LeadAngleDeg, cem.TrailAngleDeg),
        };
    }

    public static void WriteJson(GeometryMetrics oMetrics, string strPath)
        => File.WriteAllText(strPath, JsonSerializer.Serialize(oMetrics, Json));
}
