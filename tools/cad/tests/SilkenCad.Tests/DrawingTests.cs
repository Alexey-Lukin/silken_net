namespace SilkenCad.Tests;

// Pure-logic tests for the CEM-native drawing generator (tools/cad/docs/drawings_program.md). String-
// level asserts on the analytic SVG — no render, no Library.Go (Linux CI hard-gate). Confirms the drawing
// is well-formed and carries the CEM numbers (the whole point: dims come from the CEM, not a lossy mesh).
public class DrawingTests
{
    [Fact]
    public void TiCoin_Svg_Is_Wellformed_And_Carries_The_Cem_Dims()
    {
        string svg = Drawing.TiCoin(new TiCoinCem(), "test");
        Assert.StartsWith("<svg", svg);
        Assert.Contains("</svg>", svg);
        Assert.Contains("Ø16", svg);          // disc Ø straight from the CEM
        Assert.Contains("2.01 cm²", svg);     // 1 face = π·8² ≈ 2 cm² (01_03 §3.5)
        Assert.Contains("Ti-6Al-4V", svg);    // title-block material
        Assert.Contains("rev test", svg);     // injected revision (git SHA in practice)
        Assert.DoesNotContain("NaN", svg);
        Assert.DoesNotContain("Infinity", svg);
    }

    [Fact]
    public void TiCoin_Active_Window_Renders_A_Dashed_Defined_Area()
    {
        string svg = Drawing.TiCoin(new TiCoinCem { ActiveWindowDiameterMm = 8f }, "t");
        Assert.Contains("window Ø8", svg);    // defined-area note (O-ring / lacquer cell)
        Assert.Contains("stroke-dasharray", svg);
    }
}
