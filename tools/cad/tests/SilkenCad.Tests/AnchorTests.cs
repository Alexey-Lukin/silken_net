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
}
