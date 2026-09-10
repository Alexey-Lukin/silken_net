// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// One home for "where do the shipped CEM manifests live" + the enumerations that pin them. A roster
// hand-written beside a growing directory is a volatile counter in test form (DrawingTests bought that
// lesson: three of seven ti_coin SKUs rode unpinned) — so every shipped-CEM pin ENUMERATES the
// directory and a new SKU becomes pinned by existing, not by someone remembering to add a row.
internal static class CemFixtures
{
    public static string Dir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "cem"))) dir = dir.Parent;
        Assert.NotNull(dir); // no cem/ above the test binary ⇒ the test is measuring nothing
        return Path.Combine(dir!.FullName, "cem");
    }

    // File NAMES (not paths) of every shipped anchor manifest, in a stable order.
    public static string[] AnchorFiles()
        => [.. Directory.GetFiles(Dir(), "anchor_zone1.*.json")
                        .Select(Path.GetFileName)
                        .OrderBy(p => p, StringComparer.Ordinal)!];

    public static AnchorCem Anchor(string strFile)
        => Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(Dir(), strFile)));

    // The rim (periphery) gyroid period — the finest cell, hence the THINNEST wall (≈ period/10,
    // 01_01 §5.5); 0 in the manifest means "same as the core".
    public static float RimPeriodMm(AnchorCem cem)
        => cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;
}
