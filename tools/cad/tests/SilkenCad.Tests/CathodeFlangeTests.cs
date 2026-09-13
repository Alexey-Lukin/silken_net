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
    public void ShankCem_Reuses_The_Zone3_Lock_With_Opposite_Lean()
    {
        CathodeFlangeCem cem = new();
        MechanicalLockCem shank = CathodeFlange.ShankCem(cem);
        Assert.Equal(-1, shank.BarbDirection);                     // Zone-3 opposite ratchet lean (§4.3 figure)
        Assert.Equal(cem.ShankDiameterMm, shank.ShankDiameterMm);
        Assert.Equal(cem.BarbRows, shank.BarbRows);
        Assert.Equal(cem.GrooveDepthMm, shank.GrooveDepthMm);
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
