// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Text.RegularExpressions;

namespace SilkenCad.Tests;

// The VENDOR form of a sheet (⚖️ founder 2026-10-15, tools/cad/docs/drawings_program.md §8 item 5): a coupon sheet that
// leaves with the coupon letter prints its notes without our references and without `notes.extra`. The letter's copy
// region is deliberately blind to them, and these pins keep the attachment from undoing that.
public class VendorSheetTests
{
    // 🔴 The net under the author's `[[…]]` marking: the FORMS an internal reference takes in our notes, not the
    // references themselves. ⛔ Declared ceiling: a form not listed passes unseen, and a rationale clause shares no token
    // with anything — that half is held by the author's marking and the founder's read of the diff, never by this list.
    private static readonly (string Name, Regex Re)[] InternalMarkers =
    [
        ("canon doc id", new Regex(@"\b0[0-6]_0\d\b")),
        ("section sign", new Regex("§")),
        ("tracker id", new Regex(@"\b(?:HW|ARCH|FW|SEC|BIZ|UNI|OPS|INF|STK|CHEM|SLASH|E)\.\d")),
        ("DOC-T", new Regex(@"\bDOC-T\b")),
        ("canon", new Regex(@"\bcanon\b", RegexOptions.IgnoreCase)),
        ("founder", new Regex(@"\bfounder\b", RegexOptions.IgnoreCase)),
        ("verdict", new Regex(@"\bverdict\b", RegexOptions.IgnoreCase)),
        ("in-silico", new Regex(@"\bin-silico\b", RegexOptions.IgnoreCase)),
        ("bake-off", new Regex(@"\bbake-off\b", RegexOptions.IgnoreCase)),
        ("orphan", new Regex(@"\borphan\b", RegexOptions.IgnoreCase)),
        ("stage label", new Regex(@"\bStage-?\d", RegexOptions.IgnoreCase)),
        ("letter section", new Regex(@"\bRFQ \d")),
        ("code constant", new Regex(@"\bALLOY_PROPERTIES\b")),
        ("markup", new Regex(@"\[\[|\]\]|\|\|")),
        // ⊕ adversary on 3c5824590 (2026-10-15): the forms the first list missed — status words, our generation label, the
        // acronyms the letter never uses, Cyrillic in either reader, and `§` as the DXF writes it («sec.»).
        ("status word", new Regex(@"\b(?:OPEN|TBD|PLACEHOLDER)\b")),
        ("generation label", new Regex(@"\bGen \d\.\d\b|\bEBFC\b")),
        ("in silico", new Regex(@"\bin[ _]silico\b", RegexOptions.IgnoreCase)),
        ("our acronym", new Regex(@"\b(?:DET|MET)\b")),
        ("Cyrillic", new Regex(@"[\u0400-\u04FF]|\\U\+04[0-9A-F]{2}")),
        ("DXF section sign", new Regex(@"\bsec\. ?\d")),
    ];

    // 🔴 The other half the first pins lacked: a vendor projection may LOSE an instruction and stay clean of markers.
    // Each phrase that orders or forbids something, present in OUR text of a field, must reach the vendor's text of it.
    private static readonly string[] Instructions =
        ["FORBIDDEN", "MANDATORY", "x5,000", "x50,000", "H<100 ppm", "250C", "within 2h", "DECLARE", "NOT APPLIED",
         "NOT a structural", "do not substitute", "attach", "repeated", "pinhole-free", "BEFORE shipment", "BEFORE plating"];

    // Named exemptions, each with its ground — a phrase that leaves one field on purpose because the ORDER lives in another.
    private static readonly (string File, string Field, string Phrase, string Why)[] InstructionExemptions =
    [
        ("ti_coin.au.json", "inspection", "DECLARE",
         "the sentence is the laboratory's ICP-MS reading of the underlayers; the order to declare them is `process` («vendor DECLARES the process and EVERY layer thickness»), which the vendor form keeps"),
    ];

    // The manifest path is provenance the drawing standard asks for (drawings_program.md §8 item 4 — the SSOT pointer
    // beside the git SHA), so the SHEET keeps it in its title block and footer; inside a NOTE the same token is a
    // traceability pointer and goes.
    private static readonly (string Name, Regex Re) ManifestPath = ("manifest path", new Regex(@"\bcem/"));

    private static string[] Hits(string text, IEnumerable<(string Name, Regex Re)> markers)
        => [.. markers.Where(m => m.Re.IsMatch(text)).Select(m => $"{m.Name} «{m.Re.Match(text).Value}»")];

    private static string Flatten(string svg)
    {
        var parts = Regex.Matches(svg, @"<text[^>]*>(.*?)</text>")
            .Select(m => m.Groups[1].Value.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">"));
        return Regex.Replace(string.Join(' ', parts), @"\s+", " ");
    }

    private static (string Field, string? Text)[] CoreNotes(NotesSpec n) =>
    [
        ("material", n.Material), ("process", n.Process), ("surface_finish", n.SurfaceFinish), ("post_process", n.PostProcess),
        ("coating_restriction", n.CoatingRestriction), ("lattice_spec", n.LatticeSpec), ("inspection", n.Inspection),
    ];

    private static NotesSpec ShippedNotes(string strFile)
    {
        var n = Cem.Parse<TiCoinCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), strFile))).Notes;
        Assert.NotNull(n);   // a coupon with no notes would make every loop below vacuous
        return n!;
    }

    [Theory]
    [MemberData(nameof(DrawingTests.ShippedCoinCems), MemberType = typeof(DrawingTests))]
    public void Every_Note_Of_A_Shipped_Coin_Reads_Clean_In_The_Vendor_Form(string strFile)
    {
        var problems = new List<string>();
        int iFullHits = 0;
        foreach (var (field, text) in CoreNotes(ShippedNotes(strFile)))
        {
            if (string.IsNullOrWhiteSpace(text)) continue;
            iFullHits += Hits(Drawing.NoteText(text, Drawing.SheetForm.Full), InternalMarkers.Append(ManifestPath)).Length;
            string p = Drawing.NoteText(text, Drawing.SheetForm.Vendor);
            problems.AddRange(Hits(p, InternalMarkers.Append(ManifestPath)).Select(h => $"{field}: {h}"));
            // The seams a cut leaves when the author marked one character too few or too many.
            foreach (Match m in Regex.Matches(p, @"  | [,;.):]|\(\s|\(\)|^\s|\s$"))
                problems.Add($"{field}: seam «{m.Value}» at {m.Index}");
        }
        Assert.True(problems.Count == 0, $"cem/{strFile}, vendor form: {string.Join(" · ", problems)}");
        var lost = CoreNotes(ShippedNotes(strFile)).Where(f => f.Text is not null)
            .SelectMany(f => Instructions.Where(i => Drawing.NoteText(f.Text!, Drawing.SheetForm.Full).Contains(i, StringComparison.Ordinal)
                                                  && !Drawing.NoteText(f.Text!, Drawing.SheetForm.Vendor).Contains(i, StringComparison.Ordinal)
                                                  && !InstructionExemptions.Any(x => x.File == strFile && x.Field == f.Field && x.Phrase == i))
                                         .Select(i => $"{f.Field}: «{i}»")).ToArray();
        Assert.True(lost.Length == 0, $"cem/{strFile}: the vendor form LOST an instruction ours carries — {string.Join(" · ", lost)}");
        // Counter-lamp: the same detector on the FULL form must fire — otherwise it measures nothing on these notes.
        Assert.True(iFullHits > 0, $"cem/{strFile}: the marker list finds nothing even in the full form — it has gone blind");
    }

    // 🔴 Runs `Program.Draw` ITSELF, in both readers: the form is threaded through the CLI, and a sheet's own words
    // (title, subtitle, the computed lead line) are code, not manifest — the per-note pin above cannot see them.
    [Theory]
    [MemberData(nameof(DrawingTests.ShippedCoinCems), MemberType = typeof(DrawingTests))]
    public void The_Vendor_Sheet_Of_A_Shipped_Coin_Carries_No_Internal_Marker_And_No_Extra_In_Either_Reader(string strFile)
    {
        string strCem = Path.Combine(CemFixtures.Dir(), strFile);
        NotesSpec notes = ShippedNotes(strFile);
        string strOut = Path.Combine(Path.GetTempPath(), $"draw_vendor_{Guid.NewGuid():N}");
        try
        {
            Assert.Equal(0, Program.Draw(strCem, strOut, bVendor: true));
            Assert.Empty(Directory.GetFiles(strOut));                     // the vendor copy lives apart from any full sheet
            string strVendor = Path.Combine(strOut, "vendor");
            string svg = Flatten(File.ReadAllText(Directory.GetFiles(strVendor, "*.drawing.svg").Single()));
            string dxf = File.ReadAllText(Directory.GetFiles(strVendor, "*.drawing.dxf").Single());

            string[] extra = notes.Extra ?? [];
            Assert.NotEmpty(extra);                                        // else the drop below proves nothing
            foreach (var (reader, text) in new[] { ("SVG", svg), ("DXF", dxf) })
            {
                string[] hits = Hits(text, InternalMarkers);
                Assert.True(hits.Length == 0, $"cem/{strFile}, vendor {reader}: {string.Join(" · ", hits)}");
                foreach (string e in extra)
                {
                    string probe = Regex.Replace(e, @"\s+", " ")[..Math.Min(40, e.Length)];
                    Assert.DoesNotContain(reader == "DXF" ? Drawing.DxfSafe(probe) : probe, text);
                }
            }

            // The copy names its own form in both readers — `out/` and `out/vendor/` hold files of one name.
            Assert.Contains("VENDOR COPY", svg);
            Assert.Contains("VENDOR COPY", dxf);

            // Counter-lamp: the full sheet of the same manifest DOES carry markers and `extra`, and no form tag.
            Assert.Equal(0, Program.Draw(strCem, strOut));
            string full = Flatten(File.ReadAllText(Directory.GetFiles(strOut, "*.drawing.svg").Single()));
            Assert.NotEmpty(Hits(full, InternalMarkers));
            Assert.DoesNotContain("VENDOR COPY", full);
            Assert.Contains("INTERNAL COPY", full);   // the full sheet says it must not leave — a missing tag is not a mark
            Assert.Contains(Regex.Replace(extra[0], @"\s+", " ")[..Math.Min(40, extra[0].Length)], full);
        }
        finally { if (Directory.Exists(strOut)) Directory.Delete(strOut, recursive: true); }
    }

    // ⚖️ The form is ratified for the COUPON sheets only; on a part sheet `notes.extra` is shop instruction, so the flag
    // must refuse there rather than quietly answer the open question of 00_07 HW.1 — and leave no sheet behind.
    [Theory]
    [InlineData("cathode_flange.json")]
    [InlineData("anchor_zone1.pine.json")]
    [InlineData("mechanical_lock.zone1.json")]
    [InlineData("zone2_sleeve.json")]
    public void Vendor_Flag_Refuses_A_Part_Sheet_Whose_Form_Is_Not_Ratified(string strFile)
    {
        string strOut = Path.Combine(Path.GetTempPath(), $"draw_vendor_refuse_{Guid.NewGuid():N}");
        try
        {
            Assert.Equal(2, Program.Draw(Path.Combine(CemFixtures.Dir(), strFile), strOut, bVendor: true));
            Assert.False(Directory.Exists(strOut) && Directory.EnumerateFileSystemEntries(strOut, "*", SearchOption.AllDirectories).Any());
        }
        finally { if (Directory.Exists(strOut)) Directory.Delete(strOut, recursive: true); }
    }

    // 🔴 A vendor half may RENAME, never ORDER: an order the full half does not carry is a requirement with no home but the
    // drawing (adversary on 2d223f869: a vendor-only «quote a Ta-coated Ti coupon as an alternative» sat on a sheet that
    // says «HIP: NOT APPLIED» — against the letter, which routes that alternative through the full Ti route).
    private static readonly string[] OrderWords =
        ["quote", "declare", "report", "must", "shall", "required", "forbidden", "mandatory", "do not", "apply", "attach",
         "repeat", "alternative", "provide", "send"];

    [Theory]
    [MemberData(nameof(DrawingTests.ShippedCoinCems), MemberType = typeof(DrawingTests))]
    public void A_Vendor_Half_Introduces_No_Order_Its_Full_Half_Does_Not_Carry(string strFile)
    {
        var problems = new List<string>();
        int iSwaps = 0;
        foreach (var (field, text) in CoreNotes(ShippedNotes(strFile)).Concat(ShippedNotes(strFile).Extra?.Select(e => ("extra", (string?)e)) ?? []))
        {
            if (text is null) continue;
            foreach (Match mm in Regex.Matches(text, @"\[\[(.*?)\|\|(.*?)\]\]"))
            {
                iSwaps++;
                string full = mm.Groups[1].Value.ToLowerInvariant(), vendor = mm.Groups[2].Value.ToLowerInvariant();
                problems.AddRange(OrderWords.Where(w => vendor.Contains(w) && !full.Contains(w)).Select(w => $"{field}: «{w}» in «{mm.Groups[2].Value}»"));
            }
        }
        Assert.True(problems.Count == 0, $"cem/{strFile}: a vendor half adds an order — {string.Join(" · ", problems)}");
        Assert.True(iSwaps > 0, $"cem/{strFile}: no `[[full||vendor]]` swap found — the pin would be vacuous on this manifest");
    }

    // The founder's read before dispatch is this report (the verdict's weakest link): it must name every changed note
    // with BOTH texts and every dropped `extra` line — a report that skipped a field would hide the cut it exists to show.
    [Theory]
    [MemberData(nameof(DrawingTests.ShippedCoinCems), MemberType = typeof(DrawingTests))]
    public void The_Changed_Notes_Report_Names_Every_Cut_Field_And_Every_Dropped_Extra_Line(string strFile)
    {
        NotesSpec n = ShippedNotes(strFile);
        string[] report = [.. Drawing.VendorChanges(n)];
        foreach (var (field, text) in CoreNotes(n))
        {
            if (text is null || Drawing.NoteText(text, Drawing.SheetForm.Full) == Drawing.NoteText(text, Drawing.SheetForm.Vendor)) continue;
            string label = Array.Find(report, l => l.EndsWith(':') && report.Contains($"  ours:   {Drawing.NoteText(text, Drawing.SheetForm.Full)}")) ?? "";
            Assert.True(label.Length > 0, $"cem/{strFile}: {field} changed but the report does not carry it");
            Assert.Contains($"  vendor: {Drawing.NoteText(text, Drawing.SheetForm.Vendor)}", report);
        }
        Assert.Equal((n.Extra ?? []).Length, report.Count(l => l.StartsWith("extra (dropped): ", StringComparison.Ordinal)));
    }

    // A mistyped flag drew the FULL form silently — the one mistake whose product is the copy that leaves the building.
    [Theory]
    [InlineData("--vendr")]
    [InlineData("--Vendor")]
    [InlineData("vendor")]
    public void Draw_Refuses_An_Unknown_Argument_Rather_Than_Drawing_The_Full_Form(string strArg)
    {
        string strOut = Path.Combine(Path.GetTempPath(), $"draw_badflag_{Guid.NewGuid():N}");
        try
        {
            Assert.Equal(2, Program.DrawCli(["draw", Path.Combine(CemFixtures.Dir(), "ti_coin.json"), strArg], strOut));
            Assert.False(Directory.Exists(strOut));
        }
        finally { if (Directory.Exists(strOut)) Directory.Delete(strOut, recursive: true); }
    }

    [Theory]
    [InlineData("bake[[ (01_02 1.3)]]; tune", "bake (01_02 1.3); tune", "bake; tune")]
    [InlineData("NOT SPECIFIED[[ in canon]]: x", "NOT SPECIFIED in canon: x", "NOT SPECIFIED: x")]
    [InlineData("[[so report|| Report]] it", "so report it", " Report it")]
    [InlineData("plain text", "plain text", "plain text")]
    [InlineData("a[[b]]c[[d||e]]f", "abcdf", "acef")]
    public void Markup_Projects_Each_Form_Exactly(string strIn, string strFull, string strVendor)
    {
        Assert.Equal(strFull, Drawing.NoteText(strIn, Drawing.SheetForm.Full));
        Assert.Equal(strVendor, Drawing.NoteText(strIn, Drawing.SheetForm.Vendor));
    }

    // Fail-closed: a malformed manifest must draw NOTHING, never a half-projected sheet — in either form.
    [Theory]
    [InlineData("open [[never closed")]
    [InlineData("stray ]] close")]
    [InlineData("]] before [[a]]")]
    [InlineData("nested [[a [[b]] c]]")]
    [InlineData("two splits [[a||b||c]]")]
    public void Malformed_Markup_Refuses_Both_Forms(string strIn)
    {
        Assert.Throws<FormatException>(() => Drawing.NoteText(strIn, Drawing.SheetForm.Full));
        Assert.Throws<FormatException>(() => Drawing.NoteText(strIn, Drawing.SheetForm.Vendor));
    }

    // 🔴 A field marked internal END TO END would print NOT SPECIFIED IN CEM on the vendor sheet — a false statement,
    // since the CEM did specify it. The sheet refuses instead; the full form of the same note still draws.
    [Fact]
    public void A_Note_Marked_Internal_End_To_End_Refuses_The_Vendor_Sheet()
    {
        var cem = new TiCoinCem { Notes = new NotesSpec { Process = "[[ours only]]" } };
        Assert.Contains("Process: ours only", Drawing.TiCoin(cem, "t", "ti_coin.json"));
        Assert.Throws<FormatException>(() => Drawing.TiCoin(cem, "t", "ti_coin.json", form: Drawing.SheetForm.Vendor));
    }
}
