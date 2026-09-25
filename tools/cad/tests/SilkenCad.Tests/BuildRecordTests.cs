// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Security.Cryptography;
using System.Text.Json;

namespace SilkenCad.Tests;

// Build-record of one batch (BuildRecord.cs, 00_07 HW.51). Pure-managed — runs in the Linux `logic` job.
// Every assert reads the SERIALIZED record, because the JSON is the contract a reader meets decades on.
// ⛔ Declared ceilings: these pins judge the MODEL half as generated — nothing here can judge a FILLED record;
// `golden_metrics` is pinned to the committed baseline, never to a re-measurement; and the CLI wiring of
// `CAD_REV` into the verb is not pinned (CAD_REV is process-global and `Program.Draw` reads it in parallel tests).
public class BuildRecordTests
{
    private static JsonElement RecordOf(string? strCommit, params string[] aPaths)
    {
        using JsonDocument oDoc = JsonDocument.Parse(BuildRecord.ToJson(BuildRecord.Create(aPaths, strCommit)));
        return oDoc.RootElement.Clone();
    }

    private static JsonElement OnlyPart(JsonElement oRecord) => oRecord.GetProperty("parts").EnumerateArray().Single();

    private static string[] Keys(JsonElement e) => [.. e.EnumerateObject().Select(p => p.Name)];

    // Independent oracle — what `sha256sum` prints — never the helper under test.
    private static string Sha256Of(string strPath) => Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(strPath)));

    private static string CemPath(string strFile) => Path.Combine(CemFixtures.Dir(), strFile);

    public static TheoryData<string> ShippedManifests()
    {
        var data = new TheoryData<string>();
        foreach (string p in Cem.ManifestFiles(CemFixtures.Dir(), "*.json"))
            data.Add(Path.GetFileName(p));
        return data;
    }

    // 🔴 A change here is a SCHEMA change: bump `BuildRecord.Schema` in the same commit — a record already filled
    // by hand keeps the version it was cut with, and its reader must know which keys to expect.
    [Fact]
    public void The_Schema_Is_Pinned_Key_By_Key()
    {
        JsonElement r = RecordOf(null, CemPath("anchor_zone1.pine.json"));
        Assert.Equal("silkennet.build_record/1", r.GetProperty("schema").GetString());
        Assert.Equal(new[] { "schema", "_note", "generator", "parts", "vendor" }, Keys(r));
        Assert.Equal(new[] { "git_commit", "picogk_version", "absent_because" }, Keys(r.GetProperty("generator")));
        Assert.Equal(new[] { "manifest", "kind", "name", "cem_sha256", "voxel_size_mm", "golden_metrics", "absent_because" },
                     Keys(OnlyPart(r)));
        Assert.Equal(new[] { "_filled_from", "vendor_name", "batch_number", "build_number", "build_date", "material_certificate", "powder_lot" },
                     Keys(r.GetProperty("vendor")));
    }

    // The record and the sheet share ONE hashing helper, so comparing them alone would stay green if that helper
    // went wrong for both — hence the independent oracle first, then the sheet `Program.Draw` actually writes.
    [Theory]
    [MemberData(nameof(ShippedManifests))]
    public void Every_Part_Names_The_Sha256_Its_Sheet_Prints_And_Sha256sum_Would(string strFile)
    {
        string strCem = CemPath(strFile);
        string strSha = OnlyPart(RecordOf(null, strCem)).GetProperty("cem_sha256").GetString()!;
        Assert.Equal(Sha256Of(strCem), strSha);

        string strOut = Path.Combine(Path.GetTempPath(), $"br_sha_{Guid.NewGuid():N}");
        try
        {
            if (Program.Draw(strCem, strOut) != 0)
                return;   // a kind `draw` refuses has no sheet to agree with — DrawingTests names each refusal
            string dxf = File.ReadAllText(Directory.GetFiles(strOut, "*.drawing.dxf").Single());
            Assert.Contains("CEM SHA-256 (sha256sum of the SSOT manifest file): " + strSha, dxf);
        }
        finally { if (Directory.Exists(strOut)) Directory.Delete(strOut, recursive: true); }
    }

    // No shipped manifest carries a BOM, so the pin above cannot tell a BYTES hash from a hash of the decoded text —
    // and the decode strips the BOM. A vendor checks the file with `sha256sum`, i.e. the bytes.
    [Fact]
    public void A_Bom_Manifest_Is_Hashed_By_Its_Bytes_Not_Its_Text()
    {
        string strDir = Directory.CreateTempSubdirectory("br_bom_").FullName;
        try
        {
            string strBom = Path.Combine(strDir, "ti_coin.json");
            File.WriteAllBytes(strBom, [0xEF, 0xBB, 0xBF, .. File.ReadAllBytes(CemPath("ti_coin.json"))]);
            Assert.Equal(Sha256Of(strBom), OnlyPart(RecordOf(null, strBom)).GetProperty("cem_sha256").GetString());
        }
        finally { Directory.Delete(strDir, recursive: true); }
    }

    [Theory]
    [MemberData(nameof(ShippedManifests))]
    public void Golden_Metrics_Are_The_Committed_Baseline_Verbatim_Or_A_Named_Absence(string strFile)
    {
        string strCem = CemPath(strFile);
        JsonElement part = OnlyPart(RecordOf(null, strCem));
        JsonElement metrics = part.GetProperty("golden_metrics");
        string strGolden = Path.ChangeExtension(strCem, null) + ".golden.json";
        string strRef = "cem/" + Path.GetFileName(strGolden);

        if (!File.Exists(strGolden))
        {
            Assert.Equal(JsonValueKind.Null, metrics.ValueKind);
            Assert.Contains(strRef, part.GetProperty("absent_because").GetProperty("golden_metrics").GetString());
            return;
        }
        Assert.Equal(JsonValueKind.Object, metrics.ValueKind);
        Assert.Equal(strRef, metrics.GetProperty("baseline").GetString());
        using JsonDocument oGolden = JsonDocument.Parse(File.ReadAllText(strGolden));
        foreach (JsonProperty p in oGolden.RootElement.EnumerateObject().Where(p => !p.Name.StartsWith('_')))
            Assert.Equal(p.Value.GetRawText(), metrics.GetProperty(p.Name).GetRawText());   // digit for digit
    }

    // Golden.cs: a baseline does not cross grids. A manifest re-voxelled without `verify --write-golden` must not
    // hand its batch the numbers of another model.
    [Fact]
    public void A_Baseline_Measured_On_Another_Grid_Is_Not_Carried()
    {
        string strDir = Directory.CreateTempSubdirectory("br_grid_").FullName;
        try
        {
            string strSrc = CemPath("anchor_zone1.pine.json");
            string strText = File.ReadAllText(strSrc);
            const string Old = "\"voxel_size_mm\": 0.1,";
            Assert.Equal(2, strText.Split(Old).Length);   // a TEXT edit with a uniqueness assert (picogk gotcha #19)
            string strCem = Path.Combine(strDir, "anchor_zone1.pine.json");
            File.WriteAllText(strCem, strText.Replace(Old, "\"voxel_size_mm\": 0.05,"));
            File.Copy(Path.ChangeExtension(strSrc, null) + ".golden.json", Path.Combine(strDir, "anchor_zone1.pine.golden.json"));

            JsonElement part = OnlyPart(RecordOf(null, strCem));
            Assert.Equal(JsonValueKind.Null, part.GetProperty("golden_metrics").ValueKind);
            Assert.Contains("does not cross grids", part.GetProperty("absent_because").GetProperty("golden_metrics").GetString());
        }
        finally { Directory.Delete(strDir, recursive: true); }
    }

    // Loud absence in the model half, both directions: a null with no reason is a silent absence, and a reason
    // beside a value is a stale one. The shipped assemblies declare no `voxel_size_mm`, so this is not vacuous.
    [Theory]
    [MemberData(nameof(ShippedManifests))]
    public void Every_Null_In_The_Model_Half_Names_Its_Reason(string strFile)
    {
        foreach (string? strCommit in new[] { null, "0123abc" })
        {
            JsonElement r = RecordOf(strCommit, CemPath(strFile));
            Assert.Equal(strCommit, r.GetProperty("generator").GetProperty("git_commit").GetString());
            AssertEveryNullIsExplained(r.GetProperty("generator"));
            AssertEveryNullIsExplained(OnlyPart(r));
        }
    }

    private static void AssertEveryNullIsExplained(JsonElement side)
    {
        Dictionary<string, string?> reasons = side.GetProperty("absent_because").EnumerateObject()
                                                  .ToDictionary(p => p.Name, p => p.Value.GetString());
        foreach (JsonProperty p in side.EnumerateObject().Where(p => p.Name != "absent_because"))
        {
            if (p.Value.ValueKind == JsonValueKind.Null)
                Assert.False(string.IsNullOrWhiteSpace(reasons.GetValueOrDefault(p.Name)), $"`{p.Name}` is null with no reason");
            else
                Assert.False(reasons.ContainsKey(p.Name), $"`{p.Name}` carries a value AND an absence reason");
        }
        Assert.All(reasons.Keys, k => Assert.True(side.TryGetProperty(k, out _), $"a reason for `{k}`, which is no field"));
    }

    // picogk gotcha #11: a guessed batch number is a fabricated trace. Only the order fills this half.
    [Fact]
    public void The_Vendor_Half_Is_Generated_Empty_And_Says_Who_Fills_It()
    {
        JsonElement vendor = RecordOf("0123abc", CemPath("ti_coin.json")).GetProperty("vendor");
        Assert.Contains("THE ORDER", vendor.GetProperty("_filled_from").GetString());
        Assert.All(vendor.EnumerateObject().Where(p => p.Name != "_filled_from"),
                   p => Assert.True(p.Value.ValueKind == JsonValueKind.Null,
                                    $"vendor.{p.Name} is generated as {p.Value.GetRawText()} — only the order may fill it"));
    }
}
