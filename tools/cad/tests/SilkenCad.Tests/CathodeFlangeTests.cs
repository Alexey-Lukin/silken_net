// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// Pure-logic golden tests for the Zone-3 cathode flange (Деталь 3, 01_01 §1) — CEM parse + the §4.3
// shank-CEM reuse mapping + barb-profile count (the §4.3 SDF sampler, no render). The rendered assembly
// gates (solidity, bayonet-lug fusion via bbox) run in the `verify` CLI. Mirrors MechanicalLockTests.
public class CathodeFlangeTests
{
    [Fact]
    public void Cem_Parse_Reads_Frozen_And_Placeholder_Dims()
    {
        const string strJson = """{ "kind": "cathode_flange", "name": "f" }""";
        Assert.Equal("cathode_flange", Cem.Kind(strJson));

        CathodeFlangeCem cem = Cem.Parse<CathodeFlangeCem>(strJson);
        Assert.Equal(25f, cem.FlangeDiameterMm);   // frozen (01_01 §1 = Radome Ø)
        Assert.Equal(9f, cem.ShankDiameterMm);     // placeholder (HW.8)
        Assert.Equal(3, cem.BayonetLugs);
        Assert.Equal(3, cem.BarbRows);
    }

    [Fact]
    public void ShankCem_Reuses_The_Zone3_Lock_Fields()
    {
        CathodeFlangeCem cem = new();
        MechanicalLockCem shank = CathodeFlange.ShankCem(cem);
        Assert.Equal(cem.ShankDiameterMm, shank.ShankDiameterMm);
        Assert.Equal(cem.BarbRows, shank.BarbRows);
        Assert.Equal(cem.GrooveDepthMm, shank.GrooveDepthMm);
    }

    // ⚖️ 2026-09-18 (00_07 HW.26): the Zone-3 groove left the geometry. cathode_flange.json says so with explicit
    // zeros, but anchor_assembly*.json and anchor_axial_stack.json declare NO flange groove keys and build the flange
    // from the record defaults — which kept cutting the retired 12 / 1.1 / 0.2 groove into every capsule and stack
    // model after the verdict. So the roster is every shipped model that builds a flange, read as it is BUILT.
    // MUTATION: restore any one CathodeFlangeCem groove default (12 / 1.1 / 0.2) ⇒ reds, naming every model that builds it.
    [Fact]
    public void No_Shipped_Model_Builds_The_Removed_Zone3_Groove__Not_Even_From_Record_Defaults()
    {
        var aFlanges = new List<(string Name, CathodeFlangeCem Cem)>();
        foreach (string strPath in Cem.ManifestFiles(CemFixtures.Dir(), "*.json"))
        {
            string strJson = File.ReadAllText(strPath);
            CathodeFlangeCem? flange = Cem.Kind(strJson) switch
            {
                "cathode_flange" => Cem.Parse<CathodeFlangeCem>(strJson),
                "anchor_assembly" => Cem.Parse<AnchorAssemblyCem>(strJson).Flange,
                "anchor_axial_stack" => Cem.Parse<AnchorAxialStackCem>(strJson).Capsule.Flange,
                _ => null,
            };
            if (flange is not null) aFlanges.Add((Path.GetFileName(strPath), flange));
        }
        Assert.True(aFlanges.Count >= 5, "the roster must reach the flange, the capsule assemblies and the axial stack");

        string[] aGrooved = [.. aFlanges
            .Select(f => (f.Name, Shank: CathodeFlange.ShankCem(f.Cem)))
            .Where(f => f.Shank.GrooveOffsetMm != 0f || f.Shank.GrooveWidthMm != 0f || f.Shank.GrooveDepthMm != 0f)
            .Select(f => $"{f.Name} (groove {f.Shank.GrooveOffsetMm}/{f.Shank.GrooveWidthMm}/{f.Shank.GrooveDepthMm}, " +
                         $"cut={MechanicalLock.HasGroove(f.Shank)})")];
        Assert.True(aGrooved.Length == 0,
            "the removed Zone-3 groove is back in the flange these models build — an absent key fills from the record " +
            $"default (gotcha #0a), 00_07 HW.26:\n  {string.Join("\n  ", aGrooved)}");
    }

    // The Zone-3 lock SHEET (cem/mechanical_lock.zone3.json, drawn and published) tells the shop that the flange
    // part already carries its shank — and the two manifests share no source: the flange holds its own copy of
    // the shank fields (`_provenance.json` calls them mirrors of one HW.8 reconcile). This is what keeps that
    // sentence true: a reconcile that moves one copy reds here, instead of publishing a lock sheet for a shank
    // no part has. Name and voxel are set aside on purpose — one is an identity, the other an instrument choice.
    [Fact]
    public void Zone3_Lock_Manifest_Describes_The_Shank_The_Flange_Builds()
    {
        var flange = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json")));
        var lockCem = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone3.json")));
        MechanicalLockCem shank = CathodeFlange.ShankCem(flange) with { Name = lockCem.Name, VoxelSizeMm = lockCem.VoxelSizeMm };
        Assert.Equal(lockCem with { Notes = null, Tolerances = null }, shank);
    }

    [Fact]
    public void Shank_Profile_Has_The_Expected_Barb_Rows()
    {
        // Reuse the §4.3 SDF sampler (pure, no render) — barbs must equal BarbRows along the contact zone.
        CathodeFlangeCem cem = new();
        var sdf = new MechanicalLockShank(CathodeFlange.ShankCem(cem));
        float fRShank = cem.ShankDiameterMm / 2f;
        int n = 0;
        bool bIn = false;
        for (float z = cem.ContactStartMm; z <= cem.ContactStartMm + cem.ContactLengthMm + 0.0025f; z += 0.005f)
        {
            bool bTooth = (sdf.ProfileRadius(z) - fRShank) > 1e-4;
            if (bTooth && !bIn) { n++; bIn = true; }
            else if (!bTooth && bIn) { bIn = false; }
        }
        Assert.Equal(cem.BarbRows, n);
    }
}
