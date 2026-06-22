using System.Numerics;
using PicoGK;

namespace SilkenCad.Tests;

// Pure-logic golden tests — CEM parsing, gyroid SDF math, and generator selection. Fast and
// CI-friendly: no PicoGK Library.Go / display needed (only the managed SDF). The rendered-metric
// gates (porosity 65±, pore gradient, min-wall ≥ floor, manifold) run in the `verify`/`sweep`
// CLI on a PicoGK-capable runner. This is the .NET peer of `make -C firmware/test`.
public class AnchorTests
{
    [Fact]
    public void Cem_Parse_Reads_Kind_And_Defaults()
    {
        const string strJson = """{ "kind": "anchor_zone1", "name": "t", "gyroid_period_mm": 2.5 }""";
        Assert.Equal("anchor_zone1", Cem.Kind(strJson));

        AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
        Assert.Equal("t", cem.Name);
        Assert.Equal(2.5f, cem.GyroidPeriodMm);
        Assert.Equal(0f, cem.GyroidPeriodRimMm);   // absent ⇒ 0 ⇒ constant fallback
        Assert.Equal("sheet", cem.Topology);        // default topology
        Assert.Equal(0.1f, cem.VoxelSizeMm);        // default voxel
    }

    [Fact]
    public void Sheet_Gyroid_Is_Solid_On_The_Minimal_Surface()
    {
        // At the origin eq = 0, inside the wall band ⇒ negative SDF (solid).
        CartesianGyroid oGyroid = new(2.5f, 1.0f);
        Assert.True(oGyroid.fSignedDistance(Vector3.Zero) < 0f);
    }

    [Fact]
    public void Gyroid_Is_Periodic_In_One_Period()
    {
        CartesianGyroid oGyroid = new(2.5f, 1.0f);
        Vector3 vecPt = new(0.3f, 0.7f, 1.1f);
        float fHere = oGyroid.fSignedDistance(vecPt);
        float fShifted = oGyroid.fSignedDistance(vecPt + new Vector3(2.5f, 2.5f, 2.5f));
        Assert.Equal(fHere, fShifted, 3);
    }

    [Fact]
    public void Graded_Reduces_To_Core_Period_At_The_Core_Radius()
    {
        // At r = rCore the blend factor is 0 ⇒ the graded gyroid must equal the constant core gyroid.
        GradedCartesianGyroid oGraded = new(1f, 5f, 2.5f, 1.3f, 1.0f, 1.0f, bNetwork: false);
        CartesianGyroid oConst = new(2.5f, 1.0f);
        Vector3 vecPt = new(1f, 0f, 0.6f);   // |xy| = 1 = rCore
        Assert.Equal(oConst.fSignedDistance(vecPt), oGraded.fSignedDistance(vecPt), 3);
    }

    [Fact]
    public void Zoned_Uses_Core_Then_Rim_Period_Across_The_Boundary()
    {
        ZonedGyroid oZoned = new(3f, 2.5f, 1.3f, 1.0f);
        Vector3 vecCore = new(1f, 0f, 0.6f);   // r = 1 < 3 ⇒ core zone
        Vector3 vecRim = new(4f, 0f, 0.6f);    // r = 4 > 3 ⇒ rim zone
        Assert.Equal(new CartesianGyroid(2.5f, 1.0f).fSignedDistance(vecCore), oZoned.fSignedDistance(vecCore), 3);
        Assert.Equal(new CartesianGyroid(1.3f, 1.0f).fSignedDistance(vecRim), oZoned.fSignedDistance(vecRim), 3);
    }

    [Theory]
    [InlineData(2.5f, 0f, "sheet", typeof(CartesianGyroid))]          // no rim taper ⇒ constant v1
    [InlineData(2.5f, 2.0f, "sheet", typeof(GradedCartesianGyroid))]  // rim taper ⇒ continuous graded
    [InlineData(2.5f, 1.3f, "stepped", typeof(ZonedGyroid))]          // stepped topology ⇒ zoned
    public void Factory_Selects_The_Right_Generator(float fPeriod, float fRim, string strTopology, Type expected)
    {
        AnchorCem cem = new() { GyroidPeriodMm = fPeriod, GyroidPeriodRimMm = fRim, Topology = strTopology };
        Assert.IsType(expected, Zone1Anode.Gyroid(cem));
    }

    // --- ARCH.25 connectivity (pure-logic, no PicoGK Library.Go) — parity to the numeric experiment ---

    [Fact]
    public void Sheet_Gyroid_Is_Tricontinuous_Two_Open_Pore_Labyrinths()
    {
        // sheet (|eq| < 0.5w) splits the pore space into TWO disjoint labyrinths + one wall —
        // both open and percolating. 2 clusters is a topology FACT (HW.33), not a defect.
        Connectivity.Grid grid = Connectivity.SampleBox(new CartesianGyroid(2.5f, 1.0f), fExtentMm: 10f, fStepMm: 0.25f);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        Assert.Equal(2, m.PoreClusterCount);
        Assert.True(m.OpenPorosity > 0.98, $"open={m.OpenPorosity:F3}");
        Assert.True(m.ClosedPoreFraction < 0.02, $"closed={m.ClosedPoreFraction:F3}");
        Assert.True(m.PorePercolates is [true, true, true], $"perc=[{string.Join(",", m.PorePercolates)}]");
    }

    [Fact]
    public void Network_Gyroid_Is_Bicontinuous_One_Pore_One_Solid()
    {
        // network (single-sided eq) is bicontinuous: ONE pore + ONE solid network, both percolating.
        // Constant period+wall ⇒ the graded SDF reduces to a uniform network gyroid.
        GradedCartesianGyroid sdf = new(0f, 5f, 2.5f, 2.5f, 1.0f, 1.0f, bNetwork: true);
        Connectivity.Grid grid = Connectivity.SampleBox(sdf, fExtentMm: 10f, fStepMm: 0.25f);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        Assert.Equal(1, m.PoreClusterCount);
        Assert.True(m.OpenPorosity > 0.98, $"open={m.OpenPorosity:F3}");
        Assert.True(m.PorePercolates[2], "axial Z must percolate");
    }

    [Fact]
    public void Anchor_Envelope_Clips_Pore_Outside_The_Pipe()
    {
        // The bbox corner (r = outer·√2 > outer) is outside the pipe wall ⇒ Outside, never Pore;
        // and the rod's pore still percolates axially through the envelope.
        AnchorCem cem = new() { OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, LengthMm = 12f };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStepMm: 0.4f);

        Assert.Equal(Phase.Outside, grid.Cells[grid.Index(0, 0, grid.Nz / 2)]);
        ConnectivityMetrics m = Connectivity.Analyse(grid);
        Assert.True(m.OpenPorosity > 0.90, $"open={m.OpenPorosity:F3}");
        Assert.True(m.PorePercolates[2], "axial Z must percolate through the rod");
    }

    [Fact]
    public void Axial_Profile_Is_Flat_For_A_Radial_Gradient()
    {
        // The v2 gradient is RADIAL, so porosity along the axis (Z) must be ~uniform — the axial
        // golden test. A stepped SKU (radial zones) must still be axially flat.
        AnchorCem cem = new() { OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, LengthMm = 20f, GyroidPeriodRimMm = 1.3f, Topology = "stepped" };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStepMm: 0.4f);
        double[] aAxial = Connectivity.AxialProfile(grid);

        double dMin = aAxial.Min(), dMax = aAxial.Max();
        Assert.True(dMax - dMin < 0.10, $"axial porosity spread {dMax - dMin:F3} (min={dMin:F3} max={dMax:F3}) — should be ~flat");
    }

    [Fact]
    public void Monolithic_Rod_Sets_The_Gyroid_Inner_Radius__Else_Legacy_Bore()
    {
        // 01_01 §1.4: with a solid bus rod the gyroid annulus starts at the rod surface (rod/2); without one
        // it falls back to the legacy hollow bore (bore/2). The solid rod core itself is voxConstruct-added in
        // BuildMonolithic — render-verified by `verify` (Voxels need Library.Go), not unit-tested here.
        Assert.Equal(0.5f, Zone1Anode.InnerRadiusMm(new AnchorCem { BusRodDiameterMm = 1.0f }));
        Assert.Equal(0.8f, Zone1Anode.InnerRadiusMm(new AnchorCem { BoreDiameterMm = 1.6f }));  // rod==0 ⇒ legacy bore
    }
}
