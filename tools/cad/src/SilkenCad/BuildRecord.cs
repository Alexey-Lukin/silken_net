// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Reflection;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using PicoGK;

namespace SilkenCad;

// Build-record of ONE batch (00_07 HW.51 · 01_02 §6, the third traceability axis): «this batch = this commit +
// the sha256 of each manifest + the model metrics + the vendor». A printed part stays in a tree for 20–25 years,
// and until this file NOTHING tied a physical batch to the model it came from: a sheet names a MANIFEST
// (`cem_sha256` + `rev`), never a batch.
//
// Two halves, two writers:
//   · MODEL — generated here, pure-managed (no Library.Go): the commit, each manifest's sha256 (the SAME
//     bytes-hash the drawing prints — `Cem.ReadWithSha256`), the committed golden metrics, the kernel version.
//   · VENDOR — typed in by a human from the order. Generated EMPTY: every field null, never a plausible
//     placeholder (picogk gotcha #11) — a guessed batch number is a fabricated trace.
// 🔴 A null in the MODEL half is never silent: it has an entry in `absent_because` saying why (pin
//    `Every_Null_In_The_Model_Half_Names_Its_Reason`). The vendor half has ONE block note instead, because a
//    human fills it field by field and a per-field reason would go stale the moment a value lands beside it.
// ⛔ Declared ceilings:
//  1. `git_commit` is what CAD_REV SAYS, not what the tree IS — nothing compares it with HEAD or a clean tree.
//     The manifests are checkable after the fact (`_note` says how); the generator code is not.
//  2. `golden_metrics` are the committed REGRESSION baseline (Golden.cs), COPIED, not re-measured: model numbers
//     at the baseline's voxel, never the printed batch; a baseline gone stale after a manifest edit is copied as
//     it stands (only `verify` sees that); and a kind with no baseline gets none.
//  3. Nothing validates a FILLED record — the vendor half is free text the moment a human writes it.
internal static class BuildRecord
{
    // Bump on ANY change to the key set (pin `The_Schema_Is_Pinned_Key_By_Key`): a record already filled by hand
    // keeps the version it was cut with, and a reader decades on must know which keys to expect.
    internal const string Schema = "silkennet.build_record/1";

    private const string Note =
        "Build-record of ONE batch (tools/cad `build-record`, 00_07 HW.51). MODEL half generated from the tree; "
        + "VENDOR half typed in from the order. A null in the model half names its reason in `absent_because`. "
        + "Manifest paths are relative to tools/cad/. Check against the tree: "
        + "`git show <generator.git_commit>:tools/cad/<manifest> | sha256sum` must equal `cem_sha256` — a mismatch "
        + "means the record was cut from a dirty tree. `golden_metrics` = the committed regression baseline of the "
        + "MODEL at its voxel, never a measurement of the printed batch.";

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        // A human reads and fills this file: keep «—», «→» and backticks legible instead of \uXXXX. Not an HTML
        // context, so the relaxed encoder's one risk does not apply.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    internal sealed record Record(
        string Schema,
        [property: JsonPropertyName("_note")] string Note,
        Generator Generator,
        IReadOnlyList<Part> Parts,
        Vendor Vendor);

    internal sealed record Generator(string? GitCommit, string? PicogkVersion, IReadOnlyDictionary<string, string> AbsentBecause);

    internal sealed record Part(
        string Manifest,
        string Kind,
        string? Name,
        string CemSha256,
        double? VoxelSizeMm,
        IReadOnlyDictionary<string, JsonElement>? GoldenMetrics,
        IReadOnlyDictionary<string, string> AbsentBecause);

    // The fields the order returns. `powder_lot` is not in the leg's own list: it is here because the RFQ asks for
    // a CoC PER POWDER LOT (anchor_alloy_rfq §QC deliverables) and reused powder picks up oxygen lot by lot — the
    // one vendor datum a recall 15 years on would search by.
    internal sealed record Vendor
    {
        [JsonPropertyName("_filled_from")]
        public string FilledFrom { get; init; } =
            "THE ORDER, by hand (00_07 HW.51, human leg). null = NOT YET RECEIVED, never «none»: copy what the vendor's "
            + "documents say, never a guess. `material_certificate` + `powder_lot` = the CoC per powder lot the RFQ asks "
            + "for (lot/heat number, O/N/H chemistry, virgin/reuse mix — anchor_alloy_rfq §QC deliverables).";

        public string? VendorName { get; init; }
        public string? BatchNumber { get; init; }
        public string? BuildNumber { get; init; }
        public string? BuildDate { get; init; }
        public string? MaterialCertificate { get; init; }
        public string? PowderLot { get; init; }
    }

    internal static int Print(IEnumerable<string> cemPaths, string? gitCommit)
    {
        Console.Out.Write(ToJson(Create(cemPaths, gitCommit)));
        return 0;
    }

    internal static string ToJson(Record oRecord) => JsonSerializer.Serialize(oRecord, Json) + "\n";

    internal static Record Create(IEnumerable<string> cemPaths, string? gitCommit)
    {
        string? strKernel = typeof(Library).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        var oAbsent = new Dictionary<string, string>();
        if (gitCommit is null)
            oAbsent["git_commit"] = "CAD_REV not set — run `CAD_REV=$(git rev-parse HEAD) … build-record …`; without it the batch "
                                    + "names its manifests but not the generator code that turned them into geometry";
        if (strKernel is null)
            oAbsent["picogk_version"] = "the loaded PicoGK assembly carries no informational version";

        return new Record(Schema, Note, new Generator(gitCommit, strKernel, oAbsent), [.. cemPaths.Select(PartOf)], new Vendor());
    }

    private static Part PartOf(string strPath)
    {
        (string strJson, string strSha256) = Cem.ReadWithSha256(strPath);
        string strKind = Cem.Kind(strJson);
        using JsonDocument oDoc = JsonDocument.Parse(strJson);
        JsonElement oRoot = oDoc.RootElement;

        // Read what the manifest DECLARES. An undeclared field is not filled with the record default here: the
        // effective value then lives in Cem.cs (gotcha #0a), and restating it would be a second, unguarded copy.
        string? strName = oRoot.TryGetProperty("name", out JsonElement oName) ? oName.GetString() : null;
        double? dVoxel = oRoot.TryGetProperty("voxel_size_mm", out JsonElement oVoxel) ? oVoxel.GetDouble() : null;
        var oAbsent = new Dictionary<string, string>();
        if (strName is null)
            oAbsent["name"] = Undeclared("name", strKind);
        if (dVoxel is null)
            oAbsent["voxel_size_mm"] = Undeclared("voxel_size_mm", strKind);

        (Dictionary<string, JsonElement>? oGolden, string? strWhyNot) = GoldenOf(strPath, dVoxel);
        if (strWhyNot is not null)
            oAbsent["golden_metrics"] = strWhyNot;

        return new Part("cem/" + Path.GetFileName(strPath), strKind, strName, strSha256, dVoxel, oGolden, oAbsent);
    }

    private static string Undeclared(string strKey, string strKind) =>
        $"the manifest declares no `{strKey}` — build takes the Cem.cs record default of kind `{strKind}`, "
        + "which this record does not restate (picogk gotcha #0a)";

    private static (Dictionary<string, JsonElement>? Metrics, string? WhyNot) GoldenOf(string strCemPath, double? dVoxel)
    {
        string strFile = Golden.Path(strCemPath);
        string strRef = "cem/" + Path.GetFileName(strFile);
        if (!File.Exists(strFile))
            return (null, $"no committed regression baseline {strRef}");

        using JsonDocument oDoc = JsonDocument.Parse(File.ReadAllText(strFile));
        double? dBase = oDoc.RootElement.TryGetProperty("voxel_size_mm", out JsonElement oV) ? oV.GetDouble() : null;
        if (dBase is null || dVoxel is null || !Golden.SameGrid(dBase.Value, dVoxel.Value))
            return (null, $"baseline {strRef} is for voxel {dBase?.ToString() ?? "(undeclared)"} mm while the manifest builds at "
                          + $"{dVoxel?.ToString() ?? "an undeclared record-default voxel"} — a baseline does not cross grids "
                          + "(Golden.cs), so its numbers would describe another model");

        // Verbatim copy (raw number text, no float re-formatting) of every metric, beside the file it came from.
        var oOut = new Dictionary<string, JsonElement> { ["baseline"] = JsonSerializer.SerializeToElement(strRef) };
        foreach (JsonProperty p in oDoc.RootElement.EnumerateObject().Where(p => !p.Name.StartsWith('_')))
            oOut[p.Name] = p.Value.Clone();
        return (oOut, null);
    }
}
