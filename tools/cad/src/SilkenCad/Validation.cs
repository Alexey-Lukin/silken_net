// SPDX-License-Identifier: AGPL-3.0-or-later
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
    public string? Material { get; init; }                  // alloy/material from the CEM Notes (traceability; the alloy-bake-off SKU — 01_02 §2.5)
    public double? Porosity { get; init; }                  // null when no envelope is supplied (solid parts)

    // Ti-coin coupon (01_01 §6.1, null for non-coin parts): projected geometric working area for j = I/A.
    public double? ActiveElectrodeAreaCm2 { get; init; }    // 1 disc face or the defined O-ring window — target 2 cm² (01_03 §3.5)

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
    public double? GrooveDepthMm { get; init; }             // DIN-471 retaining groove depth (§4.3 B: 0.25 для Ø11)
    public double? SelfSupportFaceDeg { get; init; }        // best-orientation downfacing barb angle from horizontal; ≥45° self-supports (Ti64 LPBF: 60° → Sa≈15µm)

    // Cathode flange measurements (Деталь 3, 01_01 §1, null for non-flange parts). See Validation.MeasureFlange.
    public int? BayonetLugCount { get; init; }              // radial bayonet lugs (geometric expectation; bbox extent confirms they fused)
    public double? ActiveCathodeAreaCm2 { get; init; }      // flange side/perimeter catalytic area (O₂ ingress, 02_02 §1.2)

    // Radome measurements (Деталь 4, 02_01 §5.2, null for non-radome parts). See Validation.MeasureRadome.
    public double? HollowFraction { get; init; }            // 1 − solidVol/solidDomeVol; a proper shell ≫ 0.5 (hollow IS intended, gotcha #9 inverted)
    public double? BellRiseMm { get; init; }                // dome top over the body (bbox Z − cavity height) — anti-overgrowth shield (≥3, 01_04 §5.5)

    // Capsule-end assembly mate-audit (Деталь 3↔4, 02_02 §4, null for non-assembly). See MeasureAssembly.
    public double? BayonetZMismatchMm { get; init; }        // |radome-rim landing − O-ring target| at the bayonet datum (Z-stack reconcile, HW.8)
    public double? MateRadialGapMm { get; init; }           // radome inner-cavity R − flange R; <0 = the Ø25 disc fouls the cavity (MATE-Ø)
    public double? RfClearanceMm { get; init; }             // antenna(cavity top)↔Ti(flange face) at the datum — must ≥ 12 (02_01 §5.3)
    public double? MateInterferenceMm3 { get; init; }       // flange ∩ radome solid overlap (render) — large = parts foul, ~0 = clean mate
    public double? LugTipDiameterMm { get; init; }          // bayonet lug-tip Ø the radome socket must clear (Ø29 default vs Ø25 dome)

    // Full axial-stack press-fit mate-audit (Zone 1↔2↔3, 01_01 §1+§3, null for non-stack). See MeasureAxialStack.
    public double? Zone1SleeveInterferenceMm { get; init; } // (shaft−bore)/2 at Zone-1↔Zone-2; >0 press-fit, ~0 line-to-line, <0 clearance
    public double? SleeveZone3InterferenceMm { get; init; } // (shank−bore)/2 at Zone-2↔Zone-3; −1.0 = the Ø9-in-Ø11 gap (F1 → HW.8)
    public double? InsertionBudgetMm { get; init; }         // sleeve bore − (Zone-1 insert + Zone-3 shank); <0 ⇒ shanks collide (F2)
    public double? OverallStackLengthMm { get; init; }      // anode bottom → flange-disc top — embedded install span (F3, CODIT)
    public double? Zone1Zone2InterferenceMm3 { get; init; } // render overlap — 0 at nominal Ø11=Ø11 (surfaces touch, volumes don't; press-fit is +interference on bench)
    public double? Zone2Zone3InterferenceMm3 { get; init; } // render overlap — a thin shell = flange shoulder on the sleeve top face, NOT the shank (Ø9 floats in bore Ø11 = F1)
    public bool? BusRodClears { get; init; }                // F3 — monolithic bus rod + 2·liner ≤ cathode channel (01_01 §1.4); legacy bore≥bore when rod==0
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

    // Ti-coin golden metrics: base + the projected electrode area for j = I/A. Area is ANALYTIC from the
    // CEM (a disc face, or the defined active window if set), NOT the mesh wetted-area (which counts both
    // faces + rim + eyelet + EAAE micro-roughness — not the j-normalisation area). 01_03 §3.5: A ≈ 2 cm².
    // Projected geometric working area (cm²) for j = I/A — the disc face, or the defined O-ring/lacquer
    // window if set (01_03 §3.5). Pure (CEM-only) so the area gate is xUnit-testable without a render.
    public static double CoinAreaCm2(TiCoinCem cem)
    {
        float fWindowMm = cem.ActiveWindowDiameterMm > 0f ? cem.ActiveWindowDiameterMm : cem.DiscDiameterMm;
        return Math.PI * Math.Pow(fWindowMm / 2.0, 2) / 100.0;   // disc face mm² → cm²
    }

    public static GeometryMetrics MeasureCoin(TiCoinCem cem, Voxels voxCoin)
        => Measure(cem.Name, cem.VoxelSizeMm, voxCoin, null)
            with { ActiveElectrodeAreaCm2 = CoinAreaCm2(cem), Material = cem.Notes?.Material };

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

    // Cathode-flange golden metrics (Деталь 3, 01_01 §1): base + barb count (reuses the §4.3 shank SDF
    // sampler, same as MeasureLock) + the analytic cathode side-area (O₂, 02_02 §1.2) + the bayonet-lug
    // count. Lug fusion is gated in Program via the bbox extent (flange Ø + 2·lug protrusion).
    public static GeometryMetrics MeasureFlange(CathodeFlangeCem cem, Voxels voxFlange)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, voxFlange, null);

        var oSdf = new MechanicalLockShank(CathodeFlange.ShankCem(cem));
        float fRShank = cem.ShankDiameterMm / 2f;
        float fZ0 = cem.ContactStartMm, fZ1 = cem.ContactStartMm + cem.ContactLengthMm;
        int nBarbs = 0;
        bool bInTooth = false;
        for (float fZ = fZ0; fZ <= fZ1 + 0.0025f; fZ += 0.005f)
        {
            bool bTooth = (oSdf.ProfileRadius(fZ) - fRShank) > 1e-4;
            if (bTooth && !bInTooth) { nBarbs++; bInTooth = true; }
            else if (!bTooth && bInTooth) { bInTooth = false; }
        }

        // Cathode catalytic = the flange side/perimeter (Laccase/ZIF + PTFE-GDL, O₂ from the side, 02_02 §1.2).
        double dCathodeCm2 = Math.PI * cem.FlangeDiameterMm * cem.FlangeThicknessMm / 100.0;

        return oBase with
        {
            BarbCount = nBarbs,
            BayonetLugCount = cem.BayonetLugs,
            ActiveCathodeAreaCm2 = dCathodeCm2,
        };
    }

    // Radome golden metrics (Деталь 4, 02_01 §5.2): the part is a HOLLOW shell, so the gate is INVERTED —
    // a high hollow fraction is REQUIRED (not solidity). Hollow fraction = 1 − solidVol / solid-dome vol
    // (cylinder body + hemispherical cap); bell rise = bbox Z over the cavity height (the shield cap).
    public static GeometryMetrics MeasureRadome(RadomeCem cem, Voxels voxRadome)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, voxRadome, null);

        float fR = cem.DomeDiameterMm / 2f;
        double dSolidDome = (Math.PI * fR * fR * cem.CavityHeightMm) + ((2.0 / 3.0) * Math.PI * fR * fR * fR);
        double dHollow = dSolidDome > 0 ? 1.0 - (oBase.SolidVolumeMm3 / dSolidDome) : 0.0;

        return oBase with
        {
            HollowFraction = dHollow,
            BellRiseMm = oBase.BboxSizeMm[2] - cem.CavityHeightMm,
        };
    }

    // Capsule-end assembly mate-audit (Деталь 3↔4, 02_02 §4): the base measurement on the MERGED part +
    // the analytic mate metrics (CEM-only, from Assembly) + the one rendered metric — the flange∩radome
    // interference volume (BoolIntersect on a copy, the same primitive as MeasureAnchor's shell loop).
    // The mate metrics are findings, not pass/fail: a big interference / RF < 12 / Z-mismatch is the real
    // un-reconciled Z-stack (HW.8/HW.17), asserted by the pure xUnit suite, surfaced as ⚠ in the report.
    public static GeometryMetrics MeasureAssembly(AnchorAssemblyCem cem, AssemblyVoxels av)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, av.Merged, null);

        Voxels voxOverlap = new(av.Flange);
        voxOverlap.BoolIntersect(av.Radome);
        voxOverlap.CalculateProperties(out float fInterVol, out BBox3 _);

        return oBase with
        {
            BayonetZMismatchMm = Assembly.BayonetZMismatchMm(cem),
            MateRadialGapMm = Assembly.MateRadialGapMm(cem),
            RfClearanceMm = Assembly.RfClearanceMm(cem),
            MateInterferenceMm3 = fInterVol,
            LugTipDiameterMm = 2.0 * Assembly.LugTipRadiusMm(cem),
        };
    }

    // Zone-2 sleeve golden metrics (Деталь 2, 01_01 §1): the part is a HOLLOW tube → REUSE the radome's
    // hollow-fraction (gotcha #9 inverted — hollow is intended). Hollow = 1 − solidVol / solid-rod vol
    // (π·rOD²·L); the OD / bore / length gates live in Program (analytic against the frozen CEM).
    public static GeometryMetrics MeasureSleeve(Zone2SleeveCem cem, Voxels voxSleeve)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, voxSleeve, null);
        float fROuter = Zone2Sleeve.OuterR(cem);
        double dSolidRod = Math.PI * fROuter * fROuter * cem.LengthMm;
        double dHollow = dSolidRod > 0 ? 1.0 - (oBase.SolidVolumeMm3 / dSolidRod) : 0.0;
        return oBase with { HollowFraction = dHollow };
    }

    // Full axial-stack mate-audit (01_01 §1+§3): base on the MERGED stack + the analytic press-fit metrics
    // (CEM-only, from AxialStack) + two rendered interference volumes (BoolIntersect on copies, the same
    // primitive as MeasureAssembly). Findings, not pass/fail: the Ø9-in-Ø11 clearance (F1) is the real
    // un-reconciled state (HW.8), asserted by the pure xUnit suite, surfaced as ⚠ in the report.
    public static GeometryMetrics MeasureAxialStack(AnchorAxialStackCem cem, AxialStackVoxels sv)
    {
        GeometryMetrics oBase = Measure(cem.Name, cem.VoxelSizeMm, sv.Merged, null);

        Voxels voxZ1Z2 = new(sv.Zone1);
        voxZ1Z2.BoolIntersect(sv.Zone2);
        voxZ1Z2.CalculateProperties(out float fZ1Z2, out BBox3 _);

        Voxels voxZ2Z3 = new(sv.Zone2);
        voxZ2Z3.BoolIntersect(sv.Capsule);
        voxZ2Z3.CalculateProperties(out float fZ2Z3, out BBox3 _);

        return oBase with
        {
            Zone1SleeveInterferenceMm = AxialStack.Zone1SleeveInterferenceMm(cem),
            SleeveZone3InterferenceMm = AxialStack.SleeveZone3InterferenceMm(cem),
            InsertionBudgetMm = AxialStack.InsertionBudgetMm(cem),
            OverallStackLengthMm = AxialStack.OverallStackLengthMm(cem),
            Zone1Zone2InterferenceMm3 = fZ1Z2,
            Zone2Zone3InterferenceMm3 = fZ2Z3,
            BusRodClears = AxialStack.BusRodClears(cem),
        };
    }

    public static void WriteJson(GeometryMetrics oMetrics, string strPath)
        => File.WriteAllText(strPath, JsonSerializer.Serialize(oMetrics, Json));
}
