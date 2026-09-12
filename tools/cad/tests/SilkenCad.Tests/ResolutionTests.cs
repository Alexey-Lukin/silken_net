// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// Every shipped manifest must ask for a grid its own features fit on (Resolution.cs, 00_07 HW.51).
// Pure arithmetic over the parsed record tree — no render, no display.
public class ResolutionTests
{
    // 🔴 The exemption list is the honest half of this gate, and it is NAMED rather than numeric on
    // purpose: a threshold tuned until the tree is green stops being a measurement. Each row is a
    // feature MEASURED as under-resolved, with the reason it stays that way. A new under-resolved
    // feature is not on this list, so it reds — and a row that stops being under-resolved reds too
    // (see the dead-exemption pin below), because an exemption nobody re-measures is a graveyard.
    //
    // ⚠️ DECLARED CEILING of the exemptions on the AUDIT MODELS. `anchor_assembly*` and
    // `anchor_axial_stack` are instruments, not parts: their coarse grid is a deliberate speed choice,
    // and the quantities they exist to produce (bayonet-Z mismatch, MATE-Ø, RF clearance, press-fit
    // interference, insertion budget) do not read any of the features below. What is NOT built here is
    // the narrower check that would earn those rows honestly — "is every feature the audit MEASURES
    // adequately resolved" — so these rows rest on a reading of the code, not on a gate (00_07 HW.51).
    private static readonly Dictionary<string, string> Exempt = new()
    {
        // The one PART manifest on the list, and it is a finding rather than an accommodation:
        // `stepped` is the single SKU left on the retired sheet branch, whose 1.3 mm rim period gives
        // a 0.157 mm wall. It was already known to be below the 200 µm SLM floor (71.8 % sub-floor
        // metal); what this adds is that it is also below its OWN declared grid, i.e. every metric we
        // hold for `stepped` is measured where the wall cannot be represented. Feeds the open verdict
        // on whether `stepped` remains a candidate at all — 00_07 HW.33.
        ["anchor_zone1.stepped.json:lattice_thickness"] =
            "sheet-branch rim wall 0.157 mm, below both the SLM floor and its own voxel — 00_07 HW.33 ⚖️",

        // The liner incident itself (00_07 HW.34, measured 2026-09-12). The clearance VERDICT is
        // nominal arithmetic (`AxialStack.BusRodClears`), never a rendered measurement, so the audit's
        // number is unharmed; what the grid cannot show is already printed by the audit's own ⚠ line.
        ["anchor_axial_stack.json:capsule.flange.bus_liner_thickness_mm"] =
            "the tube cannot land at voxel 0.2 — reported by the audit's own ⚠, 00_07 HW.34",
        ["anchor_axial_stack.json:capsule.flange.rod_channel_annulus"] =
            "the same 0.175 mm annulus, stated as the mechanism rather than the symptom — 00_07 HW.34",

        // Carried geometry on the audit models: rendered because the part record owns it, not because
        // the audit reads it. Each is above one voxel, so it exists in the grid and is merely coarse.
        ["anchor_axial_stack.json:zone1.lattice_thickness"] = "audit measures the envelope, not the lattice wall",
        ["anchor_axial_stack.json:capsule.flange.barb_height_mm"] = "axial retention, not a stack measurand",
        ["anchor_axial_stack.json:capsule.flange.groove_depth_mm"] = "retaining-ring groove, not a stack measurand",
        ["anchor_axial_stack.json:capsule.radome.slot_clearance_mm"] = "bayonet entry slot, not a stack measurand",
        ["anchor_assembly.json:flange.barb_height_mm"] = "axial retention, not a capsule-end mate measurand",
        ["anchor_assembly.inboard.json:flange.barb_height_mm"] = "axial retention, not a capsule-end mate measurand",
        ["anchor_assembly.skirt.json:flange.barb_height_mm"] = "axial retention, not a capsule-end mate measurand",
    };

    public static TheoryData<string> ShippedManifests()
    {
        var data = new TheoryData<string>();
        foreach (string strPath in Cem.ManifestFiles(CemFixtures.Dir(), "*.json"))
            data.Add(Path.GetFileName(strPath));
        return data;
    }

    [Theory]
    [MemberData(nameof(ShippedManifests))]
    public void Every_Declared_Feature_Fits_On_Its_Own_Grid(string strFile)
    {
        IReadOnlyList<Resolution.Feature> aFeatures = FeaturesOf(strFile);
        var aTooThin = aFeatures
            .Where(f => !f.Represented && !Exempt.ContainsKey($"{strFile}:{f.Path}"))
            .ToList();

        Assert.True(aTooThin.Count == 0,
            $"{strFile}: {aTooThin.Count} feature(s) below {Resolution.RepresentedVoxels} voxels — at that size " +
            "the grid can drop the feature entirely and every downstream metric reads a part that does not " +
            "have it:\n  " + string.Join("\n  ", aTooThin.Select(f => f.ToString())));
    }

    // A manifest that declares NO feature is a parser failure wearing a green coat: the composite
    // records inherit ~30 defaults, so an empty list means the record tree was not walked.
    [Theory]
    [MemberData(nameof(ShippedManifests))]
    public void Every_Manifest_Yields_At_Least_One_Feature(string strFile)
    {
        Assert.True(FeaturesOf(strFile).Count > 0,
            $"{strFile} produced no measurable feature — the record tree was not walked, so the check above " +
            "is green over an empty set");
    }

    // 🔑 The exemption list must stay a LIVE measurement, not a graveyard: once a feature is resolved
    // — a coarser grid refined, a dimension grown, a manifest retired — its exemption stops describing
    // anything and silently widens the gate for whatever lands at that address next. So every row must
    // still name a feature that is genuinely under-resolved today.
    [Fact]
    public void No_Exemption_Outlives_The_Finding_That_Bought_It()
    {
        var aDead = new List<string>();
        foreach (string strKey in Exempt.Keys)
        {
            string[] aParts = strKey.Split(':', 2);
            bool bStillThin = File.Exists(Path.Combine(CemFixtures.Dir(), aParts[0]))
                && FeaturesOf(aParts[0]).Any(f => f.Path == aParts[1] && !f.Represented);
            if (!bStillThin) aDead.Add(strKey);
        }

        Assert.True(aDead.Count == 0,
            "exemption(s) no longer describing an under-resolved feature — delete the row rather than " +
            "leave it widening the gate for the next thing at that address:\n  " + string.Join("\n  ", aDead));
    }

    private static IReadOnlyList<Resolution.Feature> FeaturesOf(string strFile)
    {
        string strJson = File.ReadAllText(Path.Combine(CemFixtures.Dir(), strFile));
        return Cem.Kind(strJson) switch
        {
            "ti_coin" => Feat<TiCoinCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "anchor_zone1" => Feat<AnchorCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "mechanical_lock" => Feat<MechanicalLockCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "cathode_flange" => Feat<CathodeFlangeCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "radome" => Feat<RadomeCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "zone2_sleeve" => Feat<Zone2SleeveCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "anchor_assembly" => Feat<AnchorAssemblyCem>(strJson, (c, v) => Resolution.Features(c, v), c => c.VoxelSizeMm),
            "anchor_axial_stack" => Feat<AnchorAxialStackCem>(strJson, Resolution.Features, c => c.VoxelSizeMm),
            var strKind => throw new Xunit.Sdk.XunitException(
                $"{strFile} is kind '{strKind}', which this gate does not know — a new kind must be taught here, " +
                "never skipped, or it ships unmeasured"),
        };
    }

    private static IReadOnlyList<Resolution.Feature> Feat<T>(
        string strJson, Func<T, double, IReadOnlyList<Resolution.Feature>> fn, Func<T, float> fnVoxel)
    {
        T cem = Cem.Parse<T>(strJson);
        return fn(cem, fnVoxel(cem));
    }
}
