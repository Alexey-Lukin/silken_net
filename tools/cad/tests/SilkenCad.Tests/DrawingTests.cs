// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace SilkenCad.Tests;

// Pure-logic tests for the CEM-native drawing generator (tools/cad/docs/drawings_program.md). String-
// level asserts on the analytic SVG — no render, no Library.Go (Linux CI hard-gate). Confirms the drawing
// is well-formed and carries the CEM numbers (the whole point: dims come from the CEM, not a lossy mesh).
public class DrawingTests
{
    [Fact]
    public void TiCoin_Svg_Is_Wellformed_And_Carries_The_Cem_Dims()
    {
        string svg = Drawing.TiCoin(new TiCoinCem(), "test", "ti_coin.json");
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
        string svg = Drawing.TiCoin(new TiCoinCem(), "test", "ti_coin.json");
        Assert.Contains(Drawing.NotSpecified, svg);
        Assert.DoesNotContain("Ti-6Al-4V", svg);   // the defect this file exists to prevent
        Assert.DoesNotContain("SLM/DMLS", svg);    // process fallback — same class
    }

    // Silent DROP, the mirror of invention: a null field used to remove its whole line, so the drawing
    // looked COMPLETE and the shop had nothing to query. The note field-set is fixed — absence prints.
    [Fact]
    public void Absent_Note_Fields_Print_As_Lines_Rather_Than_Vanishing()
    {
        string svg = Drawing.TiCoin(new TiCoinCem { Notes = new NotesSpec { Material = "Ta (R05200)" } }, "t", "ti_coin.json");
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
        var cem = new TiCoinCem { Tolerances = new ToleranceSpec { Features = [new LinearToleranceSpec { Feature = "bore", PlusMm = 0.1f }] } };
        string svg = Drawing.TiCoin(cem, "t", "ti_coin.json");
        Assert.Contains($"bore: +0.1 / {Drawing.NotSpecified} mm", svg);
        Assert.DoesNotContain("0.1/0 mm", svg);
    }

    // A NAMED feature with no limits at all used to vanish from BOTH svg and dxf — the live instance is
    // `cathode_flange.json:shank_dia` (Ø9, itself an HW.8.9 placeholder). Naming it is the point.
    [Fact]
    public void Named_Feature_Without_Limits_Still_Reaches_The_Drawing()
    {
        var cem = new TiCoinCem { Tolerances = new ToleranceSpec { Features = [new LinearToleranceSpec { Feature = "shank_dia" }] } };
        Assert.Contains("shank_dia", Drawing.TiCoin(cem, "t", "ti_coin.json"));
    }

    // A part can carry MORE THAN ONE toleranced size, and until 2026-09-11 the spec held exactly one —
    // so the cathode flange, whose single slot went to `shank_dia`, had no way to give its own PRIMARY
    // DATUM (the machined bus bore) a dimensional row at all. Both must reach the sheet, and the bore's
    // band is deliberately blank: it is an open vendor question (00_07 HW.34), printed as such.
    [Fact]
    public void Every_Named_Feature_Reaches_The_Drawing__Not_Just_The_First()
    {
        var cem = new TiCoinCem
        {
            Tolerances = new ToleranceSpec
            {
                Features = [new LinearToleranceSpec { Feature = "shank_dia" },
                            new LinearToleranceSpec { Feature = "bore_dia" }],
            },
        };
        string svg = Drawing.TiCoin(cem, "t", "ti_coin.json");
        Assert.Contains("shank_dia", svg);
        Assert.Contains($"bore_dia: {Drawing.NotSpecified} / {Drawing.NotSpecified} mm", svg);
    }

    [Fact]
    public void TiCoin_Active_Window_Renders_A_Dashed_Defined_Area()
    {
        string svg = Drawing.TiCoin(new TiCoinCem { ActiveWindowDiameterMm = 8f }, "t", "ti_coin.json");
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
        string iso = Drawing.TiCoin(cem, "t", "ti_coin.json");
        Assert.Contains("no ZnO-Ta on gyroid", iso);   // note consumed from the CEM, not hard-coded
        Assert.Contains("SEM x500", iso);
        Assert.Contains("Fit: H7/s6 nominal", iso);    // tolerances block rendered
        Assert.Contains("Concentricity", iso);
        Assert.Contains("first-angle", iso);           // ISO is the default footer

        string asme = Drawing.TiCoin(cem, "t", "ti_coin.json", DrawingStandard.Asme);
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
            Assert.True(Drawing.TiCoinDxf(cem, "test", "ti_coin.json", path));
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
    private static string CemDir() => CemFixtures.Dir();

    // 🔴 The InlineData roster that stood here named THREE of the seven shipped `ti_coin.*` manifests,
    // so four alloys of the bake-off — the very SKUs whose whole point is that the metal is the
    // variable — rode unpinned. A hand-written roster beside a growing directory is the volatile
    // counter in test form: it is right the day it is written and silently narrower every day after.
    // Enumerating the directory makes a new SKU pinned by existing, not by remembering.
    public static TheoryData<string> ShippedCoinCems()
    {
        var data = new TheoryData<string>();
        foreach (string p in Cem.ManifestFiles(CemDir(), "ti_coin*.json"))
            data.Add(Path.GetFileName(p));
        return data;
    }

    [Theory]
    [MemberData(nameof(ShippedCoinCems))]
    public void Shipped_Cem_Notes_Reach_The_Dxf_Verbatim(string strFile)
    {
        string strJson = File.ReadAllText(Path.Combine(CemDir(), strFile));
        var cem = Cem.Parse<TiCoinCem>(strJson);
        string path = Path.Combine(Path.GetTempPath(), $"cem_roundtrip_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.TiCoinDxf(cem, "test", strFile, path));
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

            // HW.1 (found 2026-09-09): the SSOT line must name the REAL manifest filename, not cem.Name —
            // every ti_coin.<alloy>.json's `name` uses an underscore (ti_coin_7nb) where the file uses a
            // dot (ti_coin.7nb.json), so asserting cem.Name here would pass on the exact bug this pin exists
            // to catch. This loop already runs over all seven shipped ti_coin*.json (ShippedCoinCems), so one
            // assertion closes the SSOT-filename gap for the whole family, not just one variant.
            Assert.Contains($"SSOT cem/{strFile}", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // Alloy bake-off (01_02 §2.5): the title-block MATERIAL is read from the CEM (Notes.Material), not
    // hard-coded "Ti-6Al-4V". The SSOT row is the REAL manifest filename (HW.1, found 2026-09-09) — NOT
    // cem.Name, which uses an underscore ("ti_coin_7nb") where every real ti_coin.<alloy>.json filename
    // uses a dot ("ti_coin.7nb.json"). This CEM deliberately sets Name to the underscore form so the
    // asserts can tell the two apart: a regression back to `cem/{cem.Name}.json` would print the
    // underscore path instead — exactly the false SSOT pointer this test exists to catch.
    [Fact]
    public void TiCoin_Title_Block_And_Ssot_Are_Per_Alloy_From_The_Cem()
    {
        var cem = new TiCoinCem { Name = "ti_coin_7nb", Notes = new NotesSpec { Material = "Ti-6Al-7Nb, UNS R56700 (V-free). Chemistry per ASTM F1295 - a WROUGHT spec quoted here for COMPOSITION only" } };
        string svg = Drawing.TiCoin(cem, "t", "ti_coin.7nb.json");
        Assert.Contains("Ti-6Al-7Nb", svg);                 // title-block reflects the alloy SKU, not 4V
        Assert.Contains("cem/ti_coin.7nb.json", svg);       // SSOT row is the REAL filename (dot)…
        Assert.DoesNotContain("cem/ti_coin_7nb.json", svg); // …never cem.Name (underscore) — HW.1
    }

    // ── Cathode flange (Деталь 3) — the mirror set ───────────────────────────────────────────────
    // 🔴 `draw cathode_flange` shipped as a LIVE factory deliverable with zero tests, while the Ti-coin
    // beside it carried the whole guard set. That asymmetry is the danger, not the absence: every
    // defect the coin tests pin (invented alloy, dropped note line, fabricated zero limit, unread
    // truncation) lives in the SHARED emitters, so the flange inherited the fixes without inheriting
    // the proof — and a drawing is an acceptance contract, where a silent regress is a scrapped batch.

    [Fact]
    public void CathodeFlange_Svg_Is_Wellformed_And_Carries_The_Cem_Dims()
    {
        string svg = Drawing.CathodeFlange(new CathodeFlangeCem(), "test");
        Assert.StartsWith("<svg", svg);
        Assert.Contains("</svg>", svg);
        Assert.Contains("Ø25", svg);                 // frozen flange Ø (01_01 §1, HW.8 axial freeze)
        Assert.Contains("Ø4.5 GND pad", svg);        // Hard-Gold ENIG pad (02_02 §1.2)
        Assert.Contains("3× bayonet lug", svg);      // lug count straight from the CEM
        Assert.Contains("rev test", svg);
        Assert.DoesNotContain("NaN", svg);
        Assert.DoesNotContain("Infinity", svg);
    }

    [Fact]
    public void CathodeFlange_Empty_Cem_Prints_NOT_SPECIFIED_And_Never_Invents_The_Baseline_Alloy()
    {
        string svg = Drawing.CathodeFlange(new CathodeFlangeCem(), "test");
        Assert.Contains(Drawing.NotSpecified, svg);
        Assert.DoesNotContain("Ti-6Al-4V", svg);
        Assert.DoesNotContain("SLM/DMLS", svg);
        foreach (string label in new[] { "Material", "Process", "Surface", "Post-process", "Coating", "Lattice", "Inspect" })
            Assert.Contains($"{label}: {Drawing.NotSpecified}", svg);
    }

    [Fact]
    public void CathodeFlange_Dxf_Saves_A_Valid_File_Carrying_Cem_Dims_And_Notes()
    {
        string path = Path.Combine(Path.GetTempPath(), $"flange_test_{Guid.NewGuid():N}.dxf");
        try
        {
            var cem = new CathodeFlangeCem { Notes = new NotesSpec { SurfaceFinish = "EAAE on the catalytic face only" } };
            Assert.True(Drawing.CathodeFlangeDxf(cem, "test", path));
            string dxf = File.ReadAllText(path);
            Assert.Contains("netDxf", dxf);
            Assert.Contains("AcDbText", dxf);
            Assert.Contains("%%c25", dxf);                             // Ø25 in the DXF diameter code
            Assert.Contains("EAAE on the catalytic face only", dxf);   // CEM note consumed
            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // The round-trip gotcha #11 prescribes for EVERY `draw` kind, not only the coin: read the REAL
    // manifest and prove each non-empty note reaches the DXF through `DxfSafe`.
    [Fact]
    public void Shipped_Cathode_Flange_Notes_Reach_The_Dxf_Verbatim()
    {
        var cem = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemDir(), "cathode_flange.json")));
        string path = Path.Combine(Path.GetTempPath(), $"flange_roundtrip_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.CathodeFlangeDxf(cem, "test", path));
            string dxf = File.ReadAllText(path);
            var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish,
                                 cem.Notes?.PostProcess, cem.Notes?.CoatingRestriction,
                                 cem.Notes?.Inspection }
                         .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
            Assert.NotEmpty(fields);
            foreach (string? v in fields) Assert.Contains(Drawing.DxfSafe(v!), dxf);
            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // 🔴 HW.2: the flange goes to acceptance with a Sa/Sv row, not an empty one. The shipped manifest
    // must state the finish PER SURFACE — the catalytic face keeps the EAAE roughness that makes the
    // ECSA, the outer jacket alone gets the PEP smoothing (01_02 §1.3 Крок 7). One blanket finish on
    // this part polishes away the very surface the laccase needs.
    [Fact]
    public void Shipped_Cathode_Flange_States_A_Per_Surface_Finish_Not_A_Blanket_One()
    {
        var cem = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemDir(), "cathode_flange.json")));
        string? sf = cem.Notes?.SurfaceFinish;
        Assert.False(string.IsNullOrWhiteSpace(sf));
        Assert.Contains("Sa 0.5-5 um", sf);        // EAAE micro scale (01_02 §1.2)
        Assert.Contains("Sv 50-500 nm", sf);       // EAAE nano scale
        Assert.Contains("outer jacket", sf!);      // the PEP surface is NAMED, not implied
        Assert.Contains("NO PEP", sf!);            // …and the catalytic face is fenced off from it
    }

    // ── Mechanical lock (§4.3 shank) — the CNC groove acceptance drawing (HW.26) ─────────────────
    // 🔴 The whole point of this pair: `cem_canon_sync` pins the CEM's groove_width/depth against
    // canon §4.3 B by regex, but a machinist reads the DRAWING, not the guard's stdout — this is the
    // artefact where a human catches the same drift the guard catches by text-match. Zone-1 anchor end
    // and Zone-3 flange end share one CEM `kind`/generator (opposite ratchet lean) → both manifests
    // must draw, not just one.

    [Fact]
    public void MechanicalLock_Svg_Is_Wellformed_And_Carries_The_Cem_Dims()
    {
        string svg = Drawing.MechanicalLock(new MechanicalLockCem(), "test", "mechanical_lock.json");
        Assert.StartsWith("<svg", svg);
        Assert.Contains("</svg>", svg);
        Assert.Contains("Ø11", svg);           // shank Ø straight from the CEM default
        Assert.Contains("4× barb", svg);       // barb rows straight from the CEM
        Assert.Contains("groove 1.1×0.25 DIN-471", svg);   // the DIN-471 groove — THE feature HW.26 is about
        Assert.Contains("rev test", svg);
        Assert.DoesNotContain("NaN", svg);
        Assert.DoesNotContain("Infinity", svg);
    }

    [Fact]
    public void MechanicalLock_Empty_Cem_Prints_NOT_SPECIFIED_And_Never_Invents_The_Baseline_Alloy()
    {
        string svg = Drawing.MechanicalLock(new MechanicalLockCem(), "test", "mechanical_lock.json");
        Assert.Contains(Drawing.NotSpecified, svg);
        Assert.DoesNotContain("Ti-6Al-4V", svg);
        Assert.DoesNotContain("SLM/DMLS", svg);
        foreach (string label in new[] { "Material", "Process", "Surface", "Post-process", "Coating", "Lattice", "Inspect" })
            Assert.Contains($"{label}: {Drawing.NotSpecified}", svg);
    }

    [Fact]
    public void MechanicalLock_Dxf_Saves_A_Valid_File_Carrying_Cem_Dims_And_Notes()
    {
        string path = Path.Combine(Path.GetTempPath(), $"lock_test_{Guid.NewGuid():N}.dxf");
        try
        {
            var cem = new MechanicalLockCem { Notes = new NotesSpec { PostProcess = "CNC groove post-DMLS" } };
            Assert.True(Drawing.MechanicalLockDxf(cem, "test", "mechanical_lock.json", path));
            Assert.True(File.Exists(path));
            string dxf = File.ReadAllText(path);
            Assert.Contains("netDxf", dxf);
            Assert.Contains("AcDbText", dxf);
            Assert.Contains("%%c11", dxf);                        // Ø11 as the DXF diameter code
            Assert.Contains("CNC groove post-DMLS", dxf);         // CEM note consumed into the DXF too
            Assert.Contains("1.1x0.25", dxf);                     // groove nominal reaches the DXF (DxfSafe ×→x)
            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // A NAMED feature with no limits — the same class `Named_Feature_Without_Limits_Still_Reaches_The_
    // Drawing` pins for the coin — but here it is the LIVE state of both shipped manifests today: neither
    // cites a DIN-471 tolerance BAND (no source for one yet), so a ToleranceSpec would either fabricate a
    // number or print a named-but-unlimited feature. Absent entirely is the honest third option this file's
    // own doc-comment on `ToleranceLines` draws: "a part with no ToleranceSpec at all declares no PMI."
    [Fact]
    public void MechanicalLock_With_No_ToleranceSpec_Declares_No_Pmi_Rather_Than_A_Fabricated_Band()
    {
        string svg = Drawing.MechanicalLock(new MechanicalLockCem(), "test", "mechanical_lock.json");
        Assert.DoesNotContain("TOLERANCES / GD&T", svg);
    }

    [Theory]
    [InlineData("mechanical_lock.zone1.json", 11f, "1.1×0.25", "4× barb")]
    [InlineData("mechanical_lock.zone3.json", 9f, "1×0.3", "3× barb")]
    public void MechanicalLock_Drawing_Carries_The_Shipped_Cem_Groove_Width_And_Depth(
        string strFile, float fExpectShankDia, string strExpectGroove, string strExpectBarb)
    {
        var cem = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemDir(), strFile)));
        Assert.Equal(fExpectShankDia, cem.ShankDiameterMm);
        string svg = Drawing.MechanicalLock(cem, "test", strFile);
        Assert.Contains($"groove {strExpectGroove} DIN-471", svg);
        Assert.Contains(strExpectBarb, svg);
    }

    // 🔴 The InlineData roster from the coin's own comment: a hand-written list beside a growing
    // directory silently narrows. Zone-1 and Zone-3 are the two shipped manifests TODAY, but the
    // guarantee this test carries is "every mechanical_lock*.json round-trips," not "these two do."
    public static TheoryData<string> ShippedMechanicalLockCems()
    {
        var data = new TheoryData<string>();
        foreach (string p in Cem.ManifestFiles(CemDir(), "mechanical_lock*.json"))
            data.Add(Path.GetFileName(p));
        return data;
    }

    [Theory]
    [MemberData(nameof(ShippedMechanicalLockCems))]
    public void Shipped_Mechanical_Lock_Notes_Reach_The_Dxf_Verbatim(string strFile)
    {
        var cem = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemDir(), strFile)));
        string path = Path.Combine(Path.GetTempPath(), $"lock_roundtrip_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.MechanicalLockDxf(cem, "test", strFile, path));
            string dxf = File.ReadAllText(path);

            var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish,
                                 cem.Notes?.PostProcess, cem.Notes?.CoatingRestriction, cem.Notes?.Inspection }
                         .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
            Assert.NotEmpty(fields);   // counter-lamp — an empty NotesSpec would make this vacuous
            foreach (string? v in fields) Assert.Contains(Drawing.DxfSafe(v!), dxf);

            if (cem.Notes?.Extra is { } extra)
                foreach (string ex in extra) Assert.Contains(Drawing.DxfSafe(ex), dxf);

            Assert.DoesNotContain("NaN", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // ── The wrap/height guard: the reviewer must see what the factory sees ───────────────────────
    // 🔴 An SVG `viewBox` CLIPS. A 420-char note laid out as one `<text>` at x=20 runs past a 900-wide
    // frame and simply does not exist on screen, while the DXF ships it whole — gotcha #11's inverted
    // risk, still live in the NOTES block after the 2026-08-28 title-block fix. This asserts the cure
    // on both drawings at once: every line fits, and the canvas is tall enough to hold what was drawn.
    private static void AssertEveryLineIsInsideTheFrame(string svg)
    {
        var head = Regex.Match(svg, @"<svg[^>]*width='([\d.]+)' height='([\d.]+)'");
        Assert.True(head.Success);
        double w = double.Parse(head.Groups[1].Value, CultureInfo.InvariantCulture);
        double h = double.Parse(head.Groups[2].Value, CultureInfo.InvariantCulture);
        const double advancePerPt = 155.0 / 28.0 / 9.0;   // the same measurement Drawing.Glyph9 uses
        foreach (Match m in Regex.Matches(svg,
            @"<text x='([\d.]+)' y='([\d.]+)' font-family='monospace' font-size='([\d.]+)' text-anchor='(\w+)'[^>]*>(.*?)</text>"))
        {
            double x = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            double y = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
            double size = double.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture);
            string anchor = m.Groups[4].Value;
            string text = m.Groups[5].Value.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">");
            double width = text.Length * size * advancePerPt;
            double left = anchor == "start" ? x : anchor == "end" ? x - width : x - (width / 2);
            Assert.True(left >= 0 && left + width <= w, $"runs off the {w}-wide frame: {text}");
            Assert.True(y <= h, $"drawn below the {h}-tall frame: {text}");
        }
    }

    [Fact]
    public void Shipped_Cems_Draw_No_Text_Outside_The_Frame()
    {
        var coin = Cem.Parse<TiCoinCem>(File.ReadAllText(Path.Combine(CemDir(), "ti_coin.json")));
        var flange = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemDir(), "cathode_flange.json")));
        AssertEveryLineIsInsideTheFrame(Drawing.TiCoin(coin, "test", "ti_coin.json"));
        AssertEveryLineIsInsideTheFrame(Drawing.CathodeFlange(flange, "test"));
        foreach (string strFile in new[] { "mechanical_lock.zone1.json", "mechanical_lock.zone3.json" })
        {
            var lock_ = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemDir(), strFile)));
            AssertEveryLineIsInsideTheFrame(Drawing.MechanicalLock(lock_, "test", strFile));
        }
    }

    // The canvas must be COMPUTED, not tuned: a note long enough to wrap has to push the frame down,
    // never off it. The constant this replaced had already been retuned once for the same reason.
    // ── The PUBLISHED snapshot, which is a different artefact from the generator ─────────────────
    // 🔴 `docs/images/cad/*.drawing.svg` is committed, rendered inline on GitHub and carried by
    // `wiki:sync` — i.e. it is the drawing an outsider actually sees — and NOTHING re-runs
    // `render_gallery.sh` when the generator changes. Measured: the committed flange drawing was still
    // the pre-2026-08-28 one — no `Surface` / `Lattice` / `Inspect` lines at all (the silent-drop bug),
    // no `shank_dia` row, a `PROCESS` cut mid-word at 22 chars and a `rev local` stamp — so every
    // defect that pass removed from the code was still on public display weeks later. A fix with no
    // trigger reaches the tree and not the audience.
    //
    // ⛔ Declared ceiling, because green here is narrower than it looks: this pins CONTENT and FIT, not
    // byte-currency — a pure layout change will not red it, and the `rev` stamp is deliberately not
    // compared (it varies with the generating environment). It says nothing whatever about the PNG
    // renders in the same directory: those need a display and are not checked by anything.
    private static string GalleryDir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "docs", "images", "cad"))) dir = dir.Parent;
        Assert.NotNull(dir);
        return Path.Combine(dir!.FullName, "docs", "images", "cad");
    }

    // Flatten every <text> back into one whitespace-normalised string: the notes block WRAPS, so a long
    // CEM field is split across lines and cannot be found verbatim in the raw markup.
    private static string FlattenSvgText(string svg)
    {
        var sb = new StringBuilder();
        foreach (Match m in Regex.Matches(svg, @"<text[^>]*>(.*?)</text>"))
            sb.Append(m.Groups[1].Value.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">")).Append(' ');
        return Regex.Replace(sb.ToString(), @"\s+", " ");
    }

    [Theory]
    [InlineData("ti_coin")]
    [InlineData("cathode_flange")]
    public void Published_Gallery_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame(string strPart)
    {
        string svg = File.ReadAllText(Path.Combine(GalleryDir(), $"{strPart}.drawing.svg"));
        string strJson = File.ReadAllText(Path.Combine(CemDir(), $"{strPart}.json"));
        NotesSpec? notes = strPart == "ti_coin"
            ? Cem.Parse<TiCoinCem>(strJson).Notes
            : Cem.Parse<CathodeFlangeCem>(strJson).Notes;

        var fields = new[] { notes?.Material, notes?.Process, notes?.SurfaceFinish, notes?.PostProcess,
                             notes?.CoatingRestriction, notes?.LatticeSpec, notes?.Inspection }
                     .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
        Assert.NotEmpty(fields);   // counter-lamp: an empty NotesSpec would make the loop vacuous

        string flat = FlattenSvgText(svg);
        foreach (string? v in fields)
            Assert.Contains(Regex.Replace(v!, @"\s+", " "), flat);

        AssertEveryLineIsInsideTheFrame(svg);
    }

    // A separate Theory, not another InlineData row on the one above: that helper assumes the CEM
    // filename stem equals both the output-artefact stem AND the internal `Name` field (true for
    // ti_coin/cathode_flange, NOT for mechanical_lock — see the comment on Drawing.MechanicalLock), so
    // it needs the cem-file/gallery-file pair spelled out rather than one shared `strPart` token.
    [Theory]
    [InlineData("mechanical_lock.zone1.json", "mechanical_lock_zone1")]
    [InlineData("mechanical_lock.zone3.json", "mechanical_lock_zone3")]
    public void Published_Gallery_MechanicalLock_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame(string strCemFile, string strOutName)
    {
        string svg = File.ReadAllText(Path.Combine(GalleryDir(), $"{strOutName}.drawing.svg"));
        var cem = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemDir(), strCemFile)));

        var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish, cem.Notes?.PostProcess,
                             cem.Notes?.CoatingRestriction, cem.Notes?.LatticeSpec, cem.Notes?.Inspection }
                     .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
        Assert.NotEmpty(fields);

        string flat = FlattenSvgText(svg);
        foreach (string? v in fields)
            Assert.Contains(Regex.Replace(v!, @"\s+", " "), flat);

        AssertEveryLineIsInsideTheFrame(svg);
    }


    // ── Zone-1 anode envelope card (00_07 HW.1) ─────────────────────────────────────────────────
    // 🔴 This sheet is the CARRIER of the 01_02 §3.6 coating zone-map. Until 2026-09-11 the map had a
    // source (the CEM notes) and no carrier at all, so a shop's default would have been "coat it" on a
    // surface where any dielectric kills DET. The pins below are therefore not layout checks: they are
    // the proof that the acceptance contract leaves the manifest.

    // Directory-enumerated for the same reason as ShippedCoinCems above: a hand-written roster is a
    // volatile counter in test form, and this family grows a SKU per species.
    public static TheoryData<string> ShippedAnchorCems()
    {
        var data = new TheoryData<string>();
        foreach (string p in Cem.ManifestFiles(CemDir(), "anchor_zone1*.json"))
            data.Add(Path.GetFileName(p));
        return data;
    }

    // The round-trip row picgok gotcha #11 prescribes for every new `draw` kind: read the REAL manifest,
    // assert every non-empty note reaches the DXF through the writer's own DxfSafe mapping.
    [Theory]
    [MemberData(nameof(ShippedAnchorCems))]
    public void Shipped_Anchor_Cem_Notes_Reach_The_Dxf_Verbatim(string strFile)
    {
        var cem = Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemDir(), strFile)));
        string path = Path.Combine(Path.GetTempPath(), $"anchor_roundtrip_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.AnchorZone1Dxf(cem, "test", strFile, path));
            string dxf = File.ReadAllText(path);

            var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish,
                                 cem.Notes?.PostProcess, cem.Notes?.CoatingRestriction,
                                 cem.Notes?.LatticeSpec, cem.Notes?.Inspection }
                         .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
            Assert.NotEmpty(fields);   // counter-lamp: an empty NotesSpec would make the loop vacuous
            foreach (string? v in fields) Assert.Contains(Drawing.DxfSafe(v!), dxf);

            Assert.DoesNotContain("NaN", dxf);
            // The SSOT row names the REAL manifest filename, never cem.Name: every anchor_zone1.<sku>.json
            // carries the underscore form ("anchor_zone1_pine") where the file uses a dot — the same false
            // pointer already paid for on ti_coin and mechanical_lock (HW.1, 2026-09-09).
            Assert.Contains($"SSOT cem/{strFile}", dxf);
            Assert.DoesNotContain($"SSOT cem/{cem.Name}.json", dxf);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // 🔴 THE pin of this sheet, and it guards a REFUSAL rather than a value. 01_02 §3.6 splits Zone 1
    // into two rows with opposite coating permissions, and the surface dividing them is not a manifest
    // field and is not derivable from the geometry drawn here. A future layout pass that "tidies" the
    // leader away, or a helpful default that draws a boundary circle, would turn the sheet from a
    // question into a fabricated instruction — on the one artefact that reaches a shop floor.
    // Mutation-verified: delete the Insert(1, …) in AnchorNotes and this reds alone.
    [Fact]
    public void Anchor_Sheet_Refuses_The_Coating_Zone_Boundary_Out_Loud_In_Both_Readers()
    {
        var cem = Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemDir(), "anchor_zone1.pine.json")));
        string svg = Drawing.AnchorZone1(cem, "test", "anchor_zone1.pine.json");
        string flat = FlattenSvgText(svg);
        Assert.Contains($"coating zone boundary: {Drawing.NotSpecified}", flat);          // on the view
        Assert.Contains($"Coating zone boundary: {Drawing.NotSpecified}", flat);          // in the notes

        string path = Path.Combine(Path.GetTempPath(), $"anchor_boundary_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.AnchorZone1Dxf(cem, "test", "anchor_zone1.pine.json", path));
            // The DXF has no leader geometry, so the refusal must ride as prose — the two readers may
            // differ in FORM, never in what they are told (01_02 §6, the inverted-risk half).
            Assert.Contains(Drawing.DxfSafe($"Coating zone boundary: {Drawing.NotSpecified}"), File.ReadAllText(path));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // Canon 01_02 §6: the gyroid is a SPEC CALLOUT on an envelope, never drawn cell-by-cell — over-drawing
    // a PBF lattice promises a precision nobody measures (acceptance = Archimedes + µCT, ISO/ASTM 52900).
    // The sheet must therefore say what the lattice IS and draw only the envelope. `drawings_program.md §4`
    // used to prescribe an SDF cross-section and was RECONCILED to canon the same day (00_07 HW.1) — so this pin
    // is no longer guarding against a doc that disagrees, it is the carrier of the canon side itself: a later
    // "let's sample the SDF" pass has to argue with canon rather than drift into it.
    [Fact]
    public void Anchor_Sheet_Carries_The_Lattice_As_A_Callout_And_Never_As_A_Drawn_Profile()
    {
        var cem = Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemDir(), "anchor_zone1.pine.json")));
        string svg = Drawing.AnchorZone1(cem, "test", "anchor_zone1.pine.json");
        Assert.Contains("topology network", FlattenSvgText(svg));
        Assert.Contains("SPEC, not drawn", FlattenSvgText(svg));
        // Envelope + core + the two centre-cross dashes only: a sampled lattice contour would be hundreds.
        Assert.True(Regex.Matches(svg, "<circle").Count <= 4, "the lattice must not be drawn cell-by-cell (01_02 §6)");
    }

    // The porosity TARGET is the generator's goal; canon carries three different porosity numbers whose
    // relation is an open verdict (00_07 HW.33). Printing one bare on an acceptance contract would settle
    // by typography what nobody has settled by judgement — so the sheet must deny it in the same breath.
    [Fact]
    public void Anchor_Sheet_Never_Prints_The_Porosity_Target_As_An_Acceptance_Band()
    {
        var cem = Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemDir(), "anchor_zone1.pine.json")));
        string flat = FlattenSvgText(Drawing.AnchorZone1(cem, "test", "anchor_zone1.pine.json"));
        Assert.Contains("Porosity TARGET 65 %", flat);
        Assert.Contains("NOT the acceptance band", flat);
    }

    // 🔴 The interference line used to append a hard-coded "(Lamé, E_PEEK-aware)" to a number the CEM
    // supplies — while zone2_sleeve.json's own `fit` string says the same 5–34 µm is ISO 286, which is the
    // truth (lib/constants.py: H7 0/+18 + s6 +23/+34). Canon 01_01 §4.2 requires the drawing's µm to come
    // from the Lamé window and NOT from a blind ISO 286 lookup, so the sheet was printing the rejected
    // source under the required source's name. It hid because zone2_sleeve is the only manifest filling
    // these fields and had no `draw` kind. Invention of PROVENANCE, the third member of gotcha #11's class.
    [Fact]
    public void Interference_Line_States_The_Quantity_And_Never_Invents_Its_Provenance()
    {
        var cem = Cem.Parse<Zone2SleeveCem>(File.ReadAllText(Path.Combine(CemDir(), "zone2_sleeve.json")));
        string flat = FlattenSvgText(Drawing.Zone2Sleeve(cem, "test"));
        Assert.Contains("Interference: 5–34 µm diametral", flat);
        Assert.DoesNotContain("Lamé, E_PEEK-aware", flat);
    }

    [Fact]
    public void Zone2Sleeve_Derives_The_Wound_Diameter_Rather_Than_Quoting_It()
    {
        // OD is not a CEM field — it is bore + 2·wall, and it is the WOUND in the tree, i.e. the dim that
        // decides which trees may be instrumented at all. A hard-coded Ø15 would silently survive a wall change.
        var cem = new Zone2SleeveCem { BoreDiameterMm = 11f, WallThicknessMm = 3f };
        string flat = FlattenSvgText(Drawing.Zone2Sleeve(cem, "test"));
        Assert.Contains("Ø17", flat);
        Assert.DoesNotContain("Ø15", flat);
    }

    [Fact]
    public void Shipped_Anchor_And_Sleeve_Draw_No_Text_Outside_The_Frame()
    {
        foreach (string strFile in Cem.ManifestFiles(CemDir(), "anchor_zone1*.json"))
        {
            var cem = Cem.Parse<AnchorCem>(File.ReadAllText(strFile));
            AssertEveryLineIsInsideTheFrame(Drawing.AnchorZone1(cem, "test", Path.GetFileName(strFile)));
        }
        var sleeve = Cem.Parse<Zone2SleeveCem>(File.ReadAllText(Path.Combine(CemDir(), "zone2_sleeve.json")));
        AssertEveryLineIsInsideTheFrame(Drawing.Zone2Sleeve(sleeve, "test"));
    }

    // The published-snapshot pin, extended to the two new sheets. Same declared ceiling as the rows above:
    // it pins CONTENT and FIT, not byte-currency, and says nothing about the PNG renders beside them.
    [Theory]
    [InlineData("anchor_zone1.pine.json", "anchor_zone1_pine")]
    public void Published_Gallery_Anchor_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame(string strCemFile, string strOutName)
    {
        string svg = File.ReadAllText(Path.Combine(GalleryDir(), $"{strOutName}.drawing.svg"));
        var cem = Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemDir(), strCemFile)));

        var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish, cem.Notes?.PostProcess,
                             cem.Notes?.CoatingRestriction, cem.Notes?.LatticeSpec, cem.Notes?.Inspection }
                     .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
        Assert.NotEmpty(fields);

        string flat = FlattenSvgText(svg);
        foreach (string? v in fields)
            Assert.Contains(Regex.Replace(v!, @"\s+", " "), flat);

        AssertEveryLineIsInsideTheFrame(svg);
    }

    [Fact]
    public void Published_Gallery_Zone2Sleeve_Drawing_Carries_The_Shipped_Cem_Notes_And_Fits_Its_Frame()
    {
        string svg = File.ReadAllText(Path.Combine(GalleryDir(), "zone2_sleeve.drawing.svg"));
        var cem = Cem.Parse<Zone2SleeveCem>(File.ReadAllText(Path.Combine(CemDir(), "zone2_sleeve.json")));

        var fields = new[] { cem.Notes?.Material, cem.Notes?.Process, cem.Notes?.SurfaceFinish, cem.Notes?.PostProcess,
                             cem.Notes?.CoatingRestriction, cem.Notes?.LatticeSpec, cem.Notes?.Inspection }
                     .Where(v => !string.IsNullOrWhiteSpace(v)).ToArray();
        Assert.NotEmpty(fields);

        string flat = FlattenSvgText(svg);
        foreach (string? v in fields)
            Assert.Contains(Regex.Replace(v!, @"\s+", " "), flat);

        AssertEveryLineIsInsideTheFrame(svg);
    }

    [Fact]
    public void A_Long_Note_Grows_The_Canvas_Instead_Of_Falling_Off_It()
    {
        var plain = new TiCoinCem { Notes = new NotesSpec { Material = "Ta" } };
        var wordy = new TiCoinCem { Notes = new NotesSpec { Material = "Ta", Inspection = string.Join(" ", Enumerable.Repeat("verify", 90)) } };
        string tall = Drawing.TiCoin(wordy, "t", "ti_coin.json");
        double hPlain = double.Parse(Regex.Match(Drawing.TiCoin(plain, "t", "ti_coin.json"), @"height='([\d.]+)'").Groups[1].Value, CultureInfo.InvariantCulture);
        double hWordy = double.Parse(Regex.Match(tall, @"height='([\d.]+)'").Groups[1].Value, CultureInfo.InvariantCulture);
        Assert.True(hWordy > hPlain, "a wrapped note must grow the canvas");
        AssertEveryLineIsInsideTheFrame(tall);
        Assert.Contains("verify verify", tall);   // and the text is wrapped, never truncated away
    }
}
