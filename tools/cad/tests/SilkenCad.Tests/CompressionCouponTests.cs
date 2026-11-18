// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Globalization;
using System.Numerics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using PicoGK;

namespace SilkenCad.Tests;

// ISO 13314 compression coupon (canon 01_01 §5.2 (в), 00_07 HW.33) — the pure-managed half: the manifest and its
// record, the identity of the coupon's field with the anode's, the standard's specimen window, and what the sheet
// says about the end stock and the tolerances in BOTH readers. The rendered half (porosity, connectivity, the STL's
// bbox) needs Library.Go and lives in `verify` / `build`.
// Every pin names the mutation that reds it; each was planted and reverted on 2026-11-18.
public class CompressionCouponTests
{
    private const string File_ = "compression_coupon.json";

    private static string Json() => File.ReadAllText(Path.Combine(CemFixtures.Dir(), File_));
    private static CompressionCouponCem Shipped() => Cem.Parse<CompressionCouponCem>(Json());

    // ── The manifest and its record ─────────────────────────────────────────────────────────────

    // picogk #0b: `Cem.Parse` drops an unmapped member without a word, so a key the record has no slot for parses
    // cleanly and renders nowhere. Walks the RAW json against the record tree by reflection — the parsed record
    // cannot tell an evaporated key from one that was never written.
    // MUTATION: write a key the record does not hold into the manifest (`"edm_stok_mm": 1.5`) ⇒ reds, naming the key.
    private static List<string> KeysWithoutASlot(JsonElement obj, Type type, string strPath = "")
    {
        var aMissing = new List<string>();
        foreach (JsonProperty p in obj.EnumerateObject().Where(p => !p.Name.StartsWith('_')))
        {
            PropertyInfo? slot = type.GetProperties().FirstOrDefault(pi => JsonNamingPolicy.SnakeCaseLower.ConvertName(pi.Name) == p.Name);
            if (slot is null) { aMissing.Add(strPath + p.Name); continue; }
            Type t = Nullable.GetUnderlyingType(slot.PropertyType) ?? slot.PropertyType;
            if (p.Value.ValueKind == JsonValueKind.Object)
                aMissing.AddRange(KeysWithoutASlot(p.Value, t, $"{strPath}{p.Name}."));
            else if (p.Value.ValueKind == JsonValueKind.Array && (t.IsArray ? t.GetElementType() : t.GetGenericArguments().FirstOrDefault()) is { } tEl)
                foreach (JsonElement el in p.Value.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.Object))
                    aMissing.AddRange(KeysWithoutASlot(el, tEl, $"{strPath}{p.Name}[]."));
        }
        return aMissing;
    }

    [Fact]
    public void Every_Key_Of_The_Shipped_Manifest_Has_A_Slot_In_The_Record()
    {
        using JsonDocument doc = JsonDocument.Parse(Json());
        Assert.Empty(KeysWithoutASlot(doc.RootElement, typeof(CompressionCouponCem)));

        // The walker's own lamp: a key no record holds — at the root, in a nested block, in an array element — is named.
        using JsonDocument bad = JsonDocument.Parse(
            """{ "kind": "compression_coupon", "edm_stock_mm": 1, "notes": { "materal": "x" }, "tolerances": { "features": [ { "feature": "d", "plus": 0.1 } ] } }""");
        Assert.Equal(new[] { "edm_stock_mm", "notes.materal", "tolerances.features[].plus" },
                     KeysWithoutASlot(bad.RootElement, typeof(CompressionCouponCem)));
    }

    // The ratified specimen (canon 01_01 §5.2 (в)), value by value — and the two absences that are decisions.
    // MUTATION: `"diameter_mm": 15.0` in the manifest ⇒ reds here (and in the window pin's cell count).
    [Fact]
    public void The_Shipped_Manifest_Is_The_Ratified_Specimen()
    {
        Assert.Equal("compression_coupon", Cem.Kind(Json()));
        CompressionCouponCem cem = Shipped();
        Assert.Equal("iso13314_compression_coupon", cem.Name);
        Assert.Equal(20f, cem.DiameterMm);
        Assert.Equal(30f, cem.LengthMm);
        Assert.Equal(2.0f, cem.GyroidPeriodMm);
        Assert.Equal(0.10f, cem.GyroidWallParam);
        Assert.Equal("network", cem.Topology);
        Assert.Equal(0.65f, cem.PorosityTarget);
        Assert.Equal((0.60f, 0.70f), (cem.PorosityMin, cem.PorosityMax));
        Assert.InRange(cem.PorosityTarget, cem.PorosityMin, cem.PorosityMax);
        Assert.Null(cem.EdmEndStockMm);      // the vendor's number — absent until the vendor states it
        Assert.Null(cem.SlmMinWallMm);       // likewise
        NotesSpec n = Assert.IsType<NotesSpec>(cem.Notes);
        Assert.All(new[] { n.Material, n.Process, n.SurfaceFinish, n.PostProcess, n.CoatingRestriction, n.LatticeSpec, n.Inspection },
                   v => Assert.False(string.IsNullOrWhiteSpace(v)));
        Assert.NotEmpty(n.Extra!);
        Assert.Equal(new[] { "diameter_as_printed", "length_between_cut_faces" }, cem.Tolerances!.Features!.Select(f => f.Feature));
    }

    // picogk #0a: no geometry field may fall back to a record default — an omitted key fails the parse BY NAME.
    // The roster is every root key that is a number or the topology, read off the manifest, so a new field joins it.
    // MUTATION: drop `required` from `Topology` (or give any field a default) ⇒ that row parses and reds.
    private static List<string> GeometryKeyNames()
    {
        using JsonDocument doc = JsonDocument.Parse(Json());
        return [.. doc.RootElement.EnumerateObject()
                      .Where(p => p.Value.ValueKind == JsonValueKind.Number || p.Name is "topology" or "kind" or "name")
                      .Select(p => p.Name)];
    }

    public static TheoryData<string> GeometryKeys()
    {
        var data = new TheoryData<string>();
        foreach (string strKey in GeometryKeyNames()) data.Add(strKey);
        return data;
    }

    [Theory]
    [MemberData(nameof(GeometryKeys))]
    public void A_Manifest_That_Omits_A_Geometry_Field_Does_Not_Parse(string strKey)
    {
        JsonObject o = JsonNode.Parse(Json())!.AsObject();
        Assert.True(o.Remove(strKey));
        JsonException ex = Assert.Throws<JsonException>(() => Cem.Parse<CompressionCouponCem>(o.ToJsonString()));
        Assert.Contains(strKey, ex.Message);
    }

    [Fact]
    public void The_Geometry_Roster_Reaches_Every_Field_The_Generator_Reads()
        => Assert.Superset(
            new HashSet<string> { "voxel_size_mm", "diameter_mm", "length_mm", "gyroid_period_mm", "gyroid_wall_param", "topology", "porosity_target", "porosity_min", "porosity_max" },
            GeometryKeyNames().ToHashSet());

    // `Zone1Anode.Gyroid` reads anything that is not "network"/"stepped" as SHEET, so a typo would build the other
    // branch in silence; and a declared stock of zero is not a way to say «none».
    // MUTATION: remove the topology check in CompressionCoupon.Lattice ⇒ the first three rows build and red.
    [Theory]
    [InlineData("netwrok")]
    [InlineData("Network")]
    [InlineData("stepped")]
    public void A_Topology_The_Coupon_Does_Not_Have_Refuses(string strTopology)
        => Assert.Throws<InvalidDataException>(() => CompressionCoupon.Lattice(Shipped() with { Topology = strTopology }));

    [Theory]
    [InlineData(0f)]
    [InlineData(-1f)]
    public void A_Stock_That_Is_Not_A_Stock_Refuses(float fStock)
        => Assert.Throws<InvalidDataException>(() => CompressionCoupon.Lattice(Shipped() with { EdmEndStockMm = fStock }));

    // ── The field: the anode's, not a second gyroid ─────────────────────────────────────────────

    private static readonly Vector3[] Probes =
    [
        new(0f, 0f, 0f), new(0.3f, 0.2f, 0.1f), new(1.0f, 0.5f, 0.25f), new(-3.7f, 2.2f, 11.3f), new(5.4f, -0.6f, 29.9f),
        new(9.9f, 0.1f, 15.0f), new(-7.0f, -7.0f, 3.3f), new(0.5f, 1.5f, 1.0f), new(4.2f, 4.2f, 22.2f), new(0f, 9.5f, 7.7f),
    ];

    // The reference is the SHIPPED pine anode with its period gradient flattened to its own RIM period — so this one
    // pin holds three statements of the verdict at once: the coupon's topology and wall level are the anode
    // manifest's, its period is the anode's rim period, and the field is computed by the anode's generator.
    // Exact equality on purpose: one implementation gives one bit pattern.
    // MUTATION: in CompressionCoupon.Lattice pass `Topology = "sheet"`, or `GyroidWallParam = cem.GyroidWallParam + 0.05f`,
    //           or `GyroidPeriodMm = cem.GyroidPeriodMm * 1.25f` ⇒ reds; so does `"gyroid_wall_param": 0.15` in the manifest.
    [Fact]
    public void The_Coupon_Field_Is_The_Anode_Field_At_The_Anodes_Rim_Period()
    {
        AnchorCem pine = CemFixtures.Anchor("anchor_zone1.pine.json");
        float fRim = CemFixtures.RimPeriodMm(pine);
        IImplicit oAnode = Zone1Anode.Gyroid(pine with { GyroidPeriodMm = fRim, GyroidPeriodRimMm = fRim });
        CompressionCouponCem cem = Shipped();
        IImplicit oCoupon = Zone1Anode.Gyroid(CompressionCoupon.Lattice(cem));

        Assert.Equal(fRim, cem.GyroidPeriodMm);
        Assert.Equal(pine.GyroidWallParam, cem.GyroidWallParam);
        Assert.Equal(pine.Topology, cem.Topology);
        float[] aCoupon = [.. Probes.Select(p => oCoupon.fSignedDistance(p))];
        Assert.Equal(Probes.Select(p => oAnode.fSignedDistance(p)), aCoupon);
        Assert.Contains(aCoupon, f => f < 0f);     // the probes see metal …
        Assert.Contains(aCoupon, f => f > 0f);     // … and pore: the equality is not over a constant

        // An oracle that shares no code with the generator: the network gyroid level set at ONE period.
        double dK = 2.0 * Math.PI / cem.GyroidPeriodMm;
        foreach (Vector3 p in Probes)
        {
            double dEq = (Math.Sin(dK * p.X) * Math.Cos(dK * p.Y)) + (Math.Sin(dK * p.Y) * Math.Cos(dK * p.Z)) + (Math.Sin(dK * p.Z) * Math.Cos(dK * p.X));
            Assert.InRange(oCoupon.fSignedDistance(p) - (dEq - (0.5 * (cem.GyroidWallParam - 1.0))), -1e-4, 1e-4);
        }
    }

    // The record `verify` measures is the FINISHED specimen whatever stock the print carries, with no gradient and no wire.
    // MUTATION: `LengthMm = CompressionCoupon.PrintedLengthMm(cem)` in Lattice ⇒ reds (verify would measure the print body).
    [Fact]
    public void The_Measured_Body_Is_The_Finished_Specimen_Whatever_The_Stock()
    {
        foreach (float? fStock in new float?[] { null, 1.5f })
        {
            CompressionCouponCem cem = Shipped() with { EdmEndStockMm = fStock };
            AnchorCem lattice = CompressionCoupon.Lattice(cem);
            Assert.Equal((cem.DiameterMm, cem.LengthMm), (lattice.OuterDiameterMm, lattice.LengthMm));
            Assert.Equal(cem.GyroidPeriodMm, CemFixtures.RimPeriodMm(lattice));
            Assert.Equal(cem.GyroidPeriodMm, lattice.GyroidPeriodMm);
            Assert.Null(lattice.GyroidWallParamRim);
            Assert.Equal(0f, lattice.BusRodDiameterMm);
            Assert.Equal(cem.GyroidPeriodMm, Zone1Anode.AxialPeriodMm(lattice));
        }
        // The print body: the stock lies OUTSIDE the cut planes z = 0 and z = L, on both ends.
        CompressionCouponCem stocked = Shipped() with { EdmEndStockMm = 1.5f };
        Assert.Equal(33f, CompressionCoupon.PrintedLengthMm(stocked));
        Assert.Equal(-1.5f, CompressionCoupon.PrintedZMinMm(stocked));
        Assert.Equal(30f, CompressionCoupon.PrintedLengthMm(Shipped()));
        Assert.Equal(0f, CompressionCoupon.PrintedZMinMm(Shipped()));
    }

    // ── ISO 13314 §6.1 specimen window (canon 01_01 §5.2 (1)) ───────────────────────────────────

    // The numbers of the standard are typed HERE, independently of the constants the generator carries.
    // MUTATION: `AspectMax = 3f` or `MinDimensionMm = 5f` in CompressionCoupon ⇒ the refused rows below pass and red.
    [Fact]
    public void The_Shipped_Coupon_Sits_Inside_The_Standards_Window()
    {
        CompressionCouponCem cem = Shipped();
        Assert.InRange(cem.LengthMm / cem.DiameterMm, 1f, 2f);
        Assert.True(cem.DiameterMm >= 10f && cem.LengthMm >= 10f);
        Assert.Empty(CompressionCoupon.SpecimenFindings(cem));
        Assert.Equal((10f, 15f), CompressionCoupon.CellsAcross(cem));   // ten cells across Ø — the verdict's ground
    }

    [Theory]
    [InlineData(20f, 45f, "height/diameter")]     // 2.25 — too slender
    [InlineData(20f, 15f, "height/diameter")]     // 0.75 — too squat
    [InlineData(8f, 12f, "diameter")]             // 1.5, but Ø under 10 mm
    [InlineData(9f, 9.5f, "height")]              // both under 10 mm
    public void A_Coupon_Outside_The_Window_Is_Named(float fDiameter, float fLength, string strNamed)
    {
        IReadOnlyList<string> a = CompressionCoupon.SpecimenFindings(Shipped() with { DiameterMm = fDiameter, LengthMm = fLength });
        Assert.Contains(a, s => s.StartsWith(strNamed, StringComparison.Ordinal));
    }

    // ── The sheet, both readers ─────────────────────────────────────────────────────────────────

    private static string Flatten(string svg)
    {
        var parts = Regex.Matches(svg, @"<text[^>]*>(.*?)</text>")
            .Select(m => m.Groups[1].Value.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">"));
        return Regex.Replace(string.Join(' ', parts), @"\s+", " ");
    }

    private static (string Svg, string Flat, string Dxf) Sheets(CompressionCouponCem cem)
    {
        string svg = Drawing.CompressionCoupon(cem, "test", File_, cemSha256: "0123");
        string path = Path.Combine(Path.GetTempPath(), $"coupon_{Guid.NewGuid():N}.dxf");
        try
        {
            Assert.True(Drawing.CompressionCouponDxf(cem, "test", File_, path, cemSha256: "0123"));
            return (svg, Flatten(svg), File.ReadAllText(path));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // The SVG has a viewBox and CLIPS; a line past the frame does not exist for the reviewer (picogk #11).
    private static void AssertInsideTheFrame(string svg)
    {
        Match head = Regex.Match(svg, @"<svg[^>]*width='([\d.]+)' height='([\d.]+)'");
        Assert.True(head.Success);
        double w = double.Parse(head.Groups[1].Value, CultureInfo.InvariantCulture), h = double.Parse(head.Groups[2].Value, CultureInfo.InvariantCulture);
        const double advancePerPt = 155.0 / 28.0 / 9.0;   // the measurement Drawing.Glyph9 is derived from
        MatchCollection aText = Regex.Matches(svg,
            @"<text x='([\d.]+)' y='([\d.]+)' font-family='monospace' font-size='([\d.]+)' text-anchor='(\w+)'[^>]*>(.*?)</text>");
        Assert.True(aText.Count > 20, "the frame check ranged over almost no text");
        foreach (Match m in aText)
        {
            double x = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture), y = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
            string text = m.Groups[5].Value.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">");
            double width = text.Length * double.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture) * advancePerPt;
            double left = m.Groups[4].Value switch { "start" => x, "end" => x - width, _ => x - (width / 2) };
            Assert.True(left >= 0 && left + width <= w, $"runs off the {w}-wide frame: {text}");
            Assert.True(y <= h, $"drawn below the {h}-tall frame: {text}");
        }
    }

    private const string StockAsked = "END STOCK FOR WIRE-EDM CUT (each end): NOT SPECIFIED IN CEM";
    private const string CutPlaneLine = @"<line [^>]*stroke-width='0.6' stroke-dasharray='6 3'/>";

    // The absence this sheet exists to say: the manifest carries no stock, so BOTH readers ask for it — in the notes
    // and beside the length on the view — and draw the finished 30 mm, with no printed length beside it.
    // MUTATION: `?? 0` the stock in Drawing.CouponStockLine (print «0 mm») ⇒ reds; drop `lines.Insert(2, CouponStockLine(cem))` ⇒ reds.
    [Fact]
    public void Without_A_Stock_In_The_Manifest_Both_Readers_Ask_For_It()
    {
        CompressionCouponCem cem = Shipped();
        Assert.StartsWith(StockAsked, Drawing.CouponStockLine(cem));
        (string svg, string flat, string dxf) = Sheets(cem);

        Assert.Contains($"3. {StockAsked} — state yours; the print file is regenerated with it.", flat);
        Assert.Contains($"3. {Drawing.DxfSafe(StockAsked)} - state yours; the print file is regenerated with it.", dxf);
        Assert.Contains("end stock for the wire-EDM cut: NOT SPECIFIED IN CEM — see NOTES 3", flat);   // on the view, beside the length
        Assert.Contains(">30</text>", svg);                       // the length dimension, bare
        Assert.Contains(">Ø20</text>", svg);
        Assert.Contains("%%c20", dxf);
        Assert.DoesNotMatch(@">[\d.]+ printed</text>", svg);     // no printed-length dimension …
        Assert.DoesNotContain("PRINTED LENGTH", flat + dxf);
        Assert.Empty(Regex.Matches(svg, CutPlaneLine));           // … and no cut planes (the centre lines are 0.4 wide, these 0.6)
        AssertInsideTheFrame(svg);
    }

    // With the vendor's stock in the manifest: the printed length AND the 30 mm between the cut faces, in both readers,
    // the cut planes drawn — and the request for the stock gone.
    // MUTATION: `PrintedLengthMm = LengthMm + stock` (one end) ⇒ reds on «33»; label the cut-to-cut dimension with the
    //           printed length ⇒ reds on «30 between cut faces».
    [Theory]
    [InlineData(1.5f, "33")]
    [InlineData(2.25f, "34.5")]
    public void With_A_Stock_Both_Readers_Show_The_Printed_Length_And_The_Length_Between_The_Cuts(float fStock, string strPrinted)
    {
        CompressionCouponCem cem = Shipped() with { EdmEndStockMm = fStock };
        (string svg, string flat, string dxf) = Sheets(cem);
        string strStock = fStock.ToString("0.##", CultureInfo.InvariantCulture);

        string strLine = $"END STOCK FOR WIRE-EDM CUT (each end): {strStock} mm — PRINTED LENGTH {strPrinted} mm, 30 mm BETWEEN THE CUT FACES";
        Assert.Contains(strLine, flat);
        Assert.Contains(Drawing.DxfSafe(strLine), dxf);
        foreach (string strDim in new[] { $"{strPrinted} printed", "30 between cut faces" })
        {
            Assert.Contains($">{strDim}</text>", svg);
            Assert.Contains(strDim, dxf);
        }
        Assert.DoesNotContain(StockAsked, flat);
        Assert.DoesNotContain(Drawing.DxfSafe(StockAsked), dxf);
        Assert.Equal(2, Regex.Matches(svg, CutPlaneLine).Count);   // the two cut planes
        AssertInsideTheFrame(svg);
    }

    // The tolerance block is the manifest's: a named feature with no limits prints each side as loud absence, and a
    // limit the manifest does carry prints with its own sign.
    // MUTATION: drop `ToleranceLines(cem.Tolerances)` from either reader of the coupon sheet ⇒ reds.
    [Fact]
    public void Tolerances_Print_What_The_Manifest_Carries_And_Say_What_It_Does_Not()
    {
        (_, string flat, string dxf) = Sheets(Shipped());
        foreach (string strFeature in new[] { "diameter_as_printed", "length_between_cut_faces" })
        {
            string strRow = $"{strFeature}: NOT SPECIFIED IN CEM / NOT SPECIFIED IN CEM mm";
            Assert.Contains(strRow, flat);
            Assert.Contains(strRow, dxf);
        }

        var tol = new ToleranceSpec { Features = [new LinearToleranceSpec { Feature = "length_between_cut_faces", PlusMm = 0.05f, MinusMm = -0.05f }] };
        (_, string flat2, string dxf2) = Sheets(Shipped() with { Tolerances = tol });
        Assert.Contains("length_between_cut_faces: +0.05 / -0.05 mm", flat2);
        Assert.Contains("length_between_cut_faces: +0.05 / -0.05 mm", dxf2);
    }

    // The round-trip row of this kind (picogk #11): every note of the REAL manifest reaches both readers verbatim,
    // the lattice line prints the manifest's own fields, and the SSOT names the FILE (the specimen's `name` differs).
    // MUTATION: hand `NotesLines` a null spec in Drawing.CouponNotes, or name the SSOT from `cem.Name` in either reader ⇒ reds.
    [Fact]
    public void Shipped_Notes_Reach_Both_Readers_Verbatim()
    {
        CompressionCouponCem cem = Shipped();
        (string svg, string flat, string dxf) = Sheets(cem);
        NotesSpec n = cem.Notes!;
        string[] aNotes = [n.Material!, n.Process!, n.SurfaceFinish!, n.PostProcess!, n.CoatingRestriction!, n.LatticeSpec!, n.Inspection!, .. n.Extra!];
        Assert.True(aNotes.Length >= 8);
        foreach (string strNote in aNotes)
        {
            Assert.Contains(strNote, flat);
            Assert.Contains(Drawing.DxfSafe(strNote), dxf);
        }
        Assert.Contains("topology network; cell period 2 mm constant; wall level 0.1 (a dimensionless level", flat);
        Assert.Contains("porosity 65 % nominal (the anode parts' acceptance band is 60–70 %; the coupon's relative density is reported, not judged by this sheet)", flat);
        Assert.Contains("Specimen: cylinder Ø20 × 30 mm between the cut end faces; height/diameter 1.5; 10 lattice cells across the diameter, 15 along the height.", flat);
        Assert.Contains("minimum printable wall assumed by our own check 0.2 mm [our default, NOT your machine's figure — state yours]", flat);
        Assert.NotEqual(cem.Name, Path.GetFileNameWithoutExtension(File_));
        Assert.Contains($"SSOT cem/{File_}", flat);
        Assert.Contains($"SSOT cem/{File_}", dxf);
        Assert.DoesNotContain("NaN", flat + dxf);
        AssertInsideTheFrame(svg);
    }

    // The numbers the lattice note states in words are the fields' own — one manifest, two spellings, held together here.
    // MUTATION: `"gyroid_period_mm": 2.5` (or the band, or the level) in the manifest without its note ⇒ reds.
    [Fact]
    public void The_Lattice_Note_States_The_Fields_Own_Numbers()
    {
        CompressionCouponCem cem = Shipped();
        string strNote = cem.Notes!.LatticeSpec!;
        CultureInfo inv = CultureInfo.InvariantCulture;
        Assert.Contains($"{cem.Topology.ToUpperInvariant()} topology", strNote);
        Assert.Contains($"cell period {cem.GyroidPeriodMm.ToString("0.0", inv)} mm", strNote);
        Assert.Contains($"wall level {cem.GyroidWallParam.ToString("0.00", inv)} ", strNote);
        Assert.Contains($"Porosity {(cem.PorosityTarget * 100).ToString("0", inv)} % nominal", strNote);
        Assert.Contains($"acceptance band {(cem.PorosityMin * 100).ToString("0", inv)}-{(cem.PorosityMax * 100).ToString("0", inv)} %", strNote);
    }

    // The notes are written for the shop: no canon or tracker reference, no markup, in either reader. The forms are a
    // subset of VendorSheetTests.InternalMarkers — the vendor form is not opened for this kind, so that list does not
    // range over it; when it is, this pin gives way to the theory rows there.
    // MUTATION: append «(01_01 5.2)» or «HW.33» to any note of the manifest ⇒ reds.
    [Fact]
    public void The_Sheet_Carries_No_Internal_Reference()
    {
        (string Name, Regex Re)[] aMarkers =
        [
            ("canon doc id", new Regex(@"\b0[0-6]_0\d\b")), ("section sign", new Regex("§")), ("DXF section sign", new Regex(@"\bsec\. ?\d")),
            ("tracker id", new Regex(@"\b(?:HW|ARCH|FW|SEC|BIZ|UNI|OPS|INF|STK|CHEM|SLASH|E)\.\d")),
            ("canon", new Regex(@"\bcanon\b", RegexOptions.IgnoreCase)), ("founder", new Regex(@"\bfounder\b", RegexOptions.IgnoreCase)),
            ("verdict", new Regex(@"\bverdict\b", RegexOptions.IgnoreCase)), ("bake-off", new Regex(@"\bbake-off\b", RegexOptions.IgnoreCase)),
            ("markup", new Regex(@"\[\[|\]\]|\|\|")), ("Cyrillic", new Regex(@"[Ѐ-ӿ]|\\U\+04[0-9A-F]{2}")),
        ];
        (_, string flat, string dxf) = Sheets(Shipped());
        foreach ((string strName, Regex re) in aMarkers)
        {
            Assert.False(re.IsMatch(flat), $"SVG carries {strName}: «{re.Match(flat).Value}»");
            Assert.False(re.IsMatch(dxf), $"DXF carries {strName}: «{re.Match(dxf).Value}»");
        }
    }

    // The vendor form is a CLOSED list (drawings_program.md §8 item 5) and this kind is not on it: the flag refuses
    // out loud and leaves nothing behind, rather than printing a sheet nobody opened that form for.
    // MUTATION: add "compression_coupon" to the allow-list in Program.Draw ⇒ reds.
    [Fact]
    public void The_Vendor_Flag_Refuses_The_Coupon_Sheet()
    {
        string strOut = Path.Combine(Path.GetTempPath(), $"coupon_vendor_{Guid.NewGuid():N}");
        try
        {
            Assert.Equal(2, Program.Draw(Path.Combine(CemFixtures.Dir(), File_), strOut, bVendor: true));
            Assert.False(Directory.Exists(strOut) && Directory.EnumerateFileSystemEntries(strOut, "*", SearchOption.AllDirectories).Any(p => File.Exists(p)));
        }
        finally { if (Directory.Exists(strOut)) Directory.Delete(strOut, recursive: true); }
    }

    // ── verify's anode reference line ───────────────────────────────────────────────────────────

    // The coupon ⊥ anode line reads the shipped pine baseline from beside the manifest and applies no threshold;
    // a baseline that is not there is SAID, never skipped.
    // MUTATION: return "" when the golden is absent ⇒ reds; subtract the other way round ⇒ reds on the sign.
    [Fact]
    public void The_Anode_Reference_Line_Quotes_The_Pine_Baseline_Or_Says_It_Is_Missing()
    {
        string strCem = Path.Combine(CemFixtures.Dir(), File_);
        using JsonDocument golden = JsonDocument.Parse(File.ReadAllText(Path.Combine(CemFixtures.Dir(), Program.AnodeReferenceGolden)));
        double dAnode = golden.RootElement.GetProperty("porosity").GetDouble();

        string strLine = Program.AnodeReferenceLine(strCem, dAnode + 0.0123, 0.1f);
        Assert.Contains($"porosity {dAnode.ToString("P2", CultureInfo.InvariantCulture)}", strLine);
        Assert.Contains("coupon − anode = +1.23 pp", strLine);
        Assert.Contains("same voxel", strLine);
        Assert.Contains("no threshold", strLine);
        Assert.Contains("another voxel", Program.AnodeReferenceLine(strCem, dAnode, 0.11f));

        string strElsewhere = Path.Combine(Path.GetTempPath(), $"coupon_ref_{Guid.NewGuid():N}", File_);
        Assert.Contains("NOT FOUND", Program.AnodeReferenceLine(strElsewhere, dAnode, 0.1f));
    }
}
