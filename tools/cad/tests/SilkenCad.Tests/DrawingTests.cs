// SPDX-License-Identifier: AGPL-3.0-or-later
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
        Assert.Contains("rev test", svg);     // injected revision (git SHA in practice)
        Assert.DoesNotContain("NaN", svg);
        Assert.DoesNotContain("Infinity", svg);
    }

    // 🔴 This assert used to read `Contains("Ti-6Al-4V", svg)` on a CEM with NO notes — i.e. the suite
    // GREEN-LIT the fabrication it was supposed to guard: an empty manifest stamped the baseline alloy
    // onto a drawing whose whole purpose (alloy bake-off, 01_02 §2.5) is that the metal is the variable.
    // Inverted: an absent field must print loudly, and the baseline must NOT appear from nowhere.
    [Fact]
    public void Empty_Cem_Prints_NOT_SPECIFIED_And_Never_Invents_The_Baseline_Alloy()
    {
        string svg = Drawing.TiCoin(new TiCoinCem(), "test");
        Assert.Contains(Drawing.NotSpecified, svg);
        Assert.DoesNotContain("Ti-6Al-4V", svg);   // the defect this file exists to prevent
        Assert.DoesNotContain("SLM/DMLS", svg);    // process fallback — same class
    }

    // Silent DROP, the mirror of invention: a null field used to remove its whole line, so the drawing
    // looked COMPLETE and the shop had nothing to query. The note field-set is fixed — absence prints.
    [Fact]
    public void Absent_Note_Fields_Print_As_Lines_Rather_Than_Vanishing()
    {
        string svg = Drawing.TiCoin(new TiCoinCem { Notes = new NotesSpec { Material = "Ta (R05200)" } }, "t");
        Assert.Contains("Ta (R05200)", svg);
        foreach (string label in new[] { "Process", "Surface", "Post-process", "Coating", "Lattice", "Inspect" })
            Assert.Contains($"{label}: {Drawing.NotSpecified}", svg);
    }

    // 🔴 The single most expensive character in the tract: `?? 0` on a one-sided tolerance rendered
    // `bore: 0.1/0 mm` — a ZERO minus-limit the CEM never stated, and zero is not "unknown", it is the
    // TIGHTEST possible limit. Wrong in the expensive direction, straight onto the shop floor.
    [Fact]
    public void One_Sided_Tolerance_Never_Fabricates_A_Zero_Limit()
    {
        var cem = new TiCoinCem { Tolerances = new ToleranceSpec { Feature = "bore", PlusMm = 0.1f } };
        string svg = Drawing.TiCoin(cem, "t");
        Assert.Contains($"bore: +0.1 / {Drawing.NotSpecified} mm", svg);
        Assert.DoesNotContain("0.1/0 mm", svg);
    }

    // A NAMED feature with no limits at all used to vanish from BOTH svg and dxf — the live instance is
    // `cathode_flange.json:shank_dia` (Ø9, itself an HW.8.9 placeholder). Naming it is the point.
    [Fact]
    public void Named_Feature_Without_Limits_Still_Reaches_The_Drawing()
    {
        var cem = new TiCoinCem { Tolerances = new ToleranceSpec { Feature = "shank_dia" } };
        Assert.Contains("shank_dia", Drawing.TiCoin(cem, "t"));
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

    // ── The round-trip that closes the whole class ──────────────────────────────────────────────
    // 🔴 Every other test in this file feeds an INLINE literal CEM, so none of them can see what the
    // shipped manifests actually produce — and CI runs `verify` only, never `draw`. That gap is why a
    // silent drop and a silent invention coexisted here for weeks while the suite stayed green.
    // This test reads the REAL cem/*.json and asserts every non-empty note reaches the DXF verbatim
    // (through DxfSafe, the writer's own mapping). It catches drop, fallback, truncation and escaping
    // in one assert — the four symptoms picogk gotcha #11 lists as one class.
    private static string CemDir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "cem"))) dir = dir.Parent;
        Assert.NotNull(dir); // no cem/ above the test binary ⇒ the test is measuring nothing
        return Path.Combine(dir!.FullName, "cem");
    }

    [Theory]
    [InlineData("ti_coin.json")]
    [InlineData("ti_coin.7nb.json")]
    [InlineData("ti_coin.au.json")]
    public void Shipped_Cem_Notes_Reach_The_Dxf_Verbatim(string strFile)
    {
        string strJson = File.ReadAllText(Path.Combine(CemDir(), strFile));
        var cem = Cem.Parse<TiCoinCem>(strJson);
        string path = Path.Combine(Path.GetTempPath(), $"cem_roundtrip_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.TiCoinDxf(cem, "test", path));
            string dxf = File.ReadAllText(path);

            // Лічильник-ліхтар: без нього порожній NotesSpec зробив би цикл вакуумним.
            var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish,
                                 cem.Notes?.PostProcess, cem.Notes?.CoatingRestriction,
                                 cem.Notes?.Inspection }
                         .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
            Assert.NotEmpty(fields);

            foreach (string? v in fields) Assert.Contains(Drawing.DxfSafe(v!), dxf);

            // Той самий маніфест не сміє нести й вигаданого: якщо поле є, маркер відсутності не
            // з'являється замість нього (і навпаки — це ловить попередній цикл).
            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // Alloy bake-off (01_02 §2.5): the title-block MATERIAL + SSOT row are read from the CEM
    // (Notes.Material + Name), not hard-coded "Ti-6Al-4V" / "cem/ti_coin.json".
    [Fact]
    public void TiCoin_Title_Block_And_Ssot_Are_Per_Alloy_From_The_Cem()
    {
        var cem = new TiCoinCem { Name = "ti_coin_7nb", Notes = new NotesSpec { Material = "Ti-6Al-7Nb (ASTM F1295, V-free)" } };
        string svg = Drawing.TiCoin(cem, "t");
        Assert.Contains("Ti-6Al-7Nb", svg);              // title-block reflects the alloy SKU, not 4V
        Assert.Contains("cem/ti_coin_7nb.json", svg);    // SSOT row is the per-alloy CEM name
    }
}
