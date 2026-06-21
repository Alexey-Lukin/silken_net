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

    // The whole Phase-1 point: notes/tolerances come from the CEM (Noyron-clean), and the standard is a
    // parameter (drift #3 — no more hard-coded `first-angle (ISO)`).
    [Fact]
    public void TiCoin_Svg_Consumes_Cem_Notes_Tolerances_And_Standard_Param()
    {
        var cem = new TiCoinCem
        {
            Notes = new NotesSpec { CoatingRestriction = "no ZnO-Ta on gyroid", Inspection = "SEM x500" },
            Tolerances = new ToleranceSpec { Fit = "H7/s6 nominal", ConcentricityMm = "0.05" },
        };
        string iso = Drawing.TiCoin(cem, "t");
        Assert.Contains("no ZnO-Ta on gyroid", iso);   // note consumed from the CEM, not hard-coded
        Assert.Contains("SEM x500", iso);
        Assert.Contains("Fit: H7/s6 nominal", iso);    // tolerances block rendered
        Assert.Contains("Concentricity", iso);
        Assert.Contains("first-angle", iso);           // ISO is the default footer

        string asme = Drawing.TiCoin(cem, "t", DrawingStandard.Asme);
        Assert.Contains("third-angle", asme);          // standard is a real parameter now
        Assert.Contains("Y14.5", asme);
    }

    [Fact]
    public void TiCoin_Dxf_Saves_A_Valid_File_Carrying_Cem_Dims_And_Notes()
    {
        string path = Path.Combine(Path.GetTempPath(), $"ti_coin_test_{Guid.NewGuid():N}.dxf");
        try
        {
            var cem = new TiCoinCem { Notes = new NotesSpec { CoatingRestriction = "ZnO-Ta forbidden on gyroid" } };
            Assert.True(Drawing.TiCoinDxf(cem, "test", path));
            Assert.True(File.Exists(path));
            string dxf = File.ReadAllText(path);
            Assert.Contains("netDxf", dxf);                 // valid netDxf header
            Assert.Contains("AcDbText", dxf);               // text entities present
            Assert.Contains("%%c16", dxf);                  // Ø16 as the DXF single-line diameter code
            Assert.Contains("ZnO-Ta forbidden", dxf);       // CEM note consumed into the DXF too
            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
