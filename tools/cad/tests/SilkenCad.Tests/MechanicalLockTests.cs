using System.Numerics;

namespace SilkenCad.Tests;

// Pure-logic golden tests for the §4.3 mechanical-lock shank — CEM parse + the ratchet/groove SDF math.
// No PicoGK Library.Go (only the managed SDF), like the gyroid tests. The rendered gates (volume, barb
// count vs render, manifold) run in the `verify` CLI on a PicoGK runner.
public class MechanicalLockTests
{
    private static MechanicalLockCem MkCem(int iDir = 1) => new()
    {
        ShankDiameterMm = 11f, ShankLengthMm = 18f,
        ContactStartMm = 2f, ContactLengthMm = 12f,
        BarbRows = 4, BarbHeightMm = 0.28f, LeadAngleDeg = 30f, TrailAngleDeg = 70f,
        BarbDirection = iDir,
        GrooveOffsetMm = 15f, GrooveWidthMm = 0.8f, GrooveDepthMm = 0.6f,
    };

    [Fact]
    public void Cem_Parse_Reads_Kind_And_Defaults()
    {
        const string strJson = """{ "kind": "mechanical_lock", "name": "t", "barb_rows": 3 }""";
        Assert.Equal("mechanical_lock", SilkenCad.Cem.Kind(strJson));

        MechanicalLockCem cem = SilkenCad.Cem.Parse<MechanicalLockCem>(strJson);
        Assert.Equal("t", cem.Name);
        Assert.Equal(3, cem.BarbRows);
        Assert.Equal(0.28f, cem.BarbHeightMm);   // default
        Assert.Equal(0.05f, cem.VoxelSizeMm);    // default voxel
        Assert.Equal(1, cem.BarbDirection);      // default lean
    }

    [Fact]
    public void Base_Cylinder_Solid_Inside_Void_Outside()
    {
        var sdf = new MechanicalLockShank(MkCem());
        // Before the contact zone (starts at z=2), R(z) = rShank = 5.5: r<5.5 solid, r>5.5 void.
        Assert.True(sdf.fSignedDistance(new Vector3(5.0f, 0f, 0.5f)) < 0f, "inside base cylinder");
        Assert.True(sdf.fSignedDistance(new Vector3(6.0f, 0f, 0.5f)) > 0f, "outside base cylinder");
    }

    [Fact]
    public void Barb_Ridge_Adds_Metal_Over_The_Gap()
    {
        MechanicalLockCem cem = MkCem();
        var sdf = new MechanicalLockShank(cem);
        float fRShank = cem.ShankDiameterMm / 2f;
        float fProbe = fRShank + (0.5f * cem.BarbHeightMm);   // half-height ⇒ solid only where a tooth rises
        float fPitch = cem.ContactLengthMm / cem.BarbRows;    // 3 mm
        float fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);
        float fZPeak = cem.ContactStartMm + fLeadLen;         // tip of tooth 0
        float fZGap = cem.ContactStartMm + fPitch - 0.05f;    // just before tooth 1 ⇒ flat cylinder

        Assert.True(sdf.fSignedDistance(new Vector3(fProbe, 0f, fZPeak)) < 0f, "tooth fills half-height");
        Assert.True(sdf.fSignedDistance(new Vector3(fProbe, 0f, fZGap)) > 0f, "gap is empty at half-height");
    }

    [Fact]
    public void Tooth_Count_Equals_Rows()
    {
        MechanicalLockCem cem = MkCem();
        var sdf = new MechanicalLockShank(cem);
        float fProbe = (cem.ShankDiameterMm / 2f) + (0.5f * cem.BarbHeightMm);

        int nRuns = 0;
        bool bIn = false;
        for (float fZ = cem.ContactStartMm; fZ <= cem.ContactStartMm + cem.ContactLengthMm; fZ += 0.01f)
        {
            bool bSolid = sdf.fSignedDistance(new Vector3(fProbe, 0f, fZ)) < 0f;
            if (bSolid && !bIn) nRuns++;
            bIn = bSolid;
        }
        Assert.Equal(cem.BarbRows, nRuns);
    }

    [Fact]
    public void Ratchet_Is_Asymmetric_Leading_Shallower_Than_Trailing()
    {
        MechanicalLockCem cem = MkCem();
        var sdf = new MechanicalLockShank(cem);
        float fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);
        float fTrailLen = cem.BarbHeightMm / MathF.Tan(cem.TrailAngleDeg * MathF.PI / 180f);

        // Leading ramp (easy insert) is longer than the trailing ramp (hard pull-out) — the ratchet.
        Assert.True(fLeadLen > fTrailLen, $"lead {fLeadLen:F3} should exceed trail {fTrailLen:F3}");
        // And the profile rises monotonically up the leading ramp to the peak.
        float fZ0 = cem.ContactStartMm;
        Assert.True(sdf.ProfileRadius(fZ0 + (fLeadLen / 2f)) < sdf.ProfileRadius(fZ0 + fLeadLen));
    }

    [Fact]
    public void Groove_Removes_Metal_Below_The_Shank_Radius()
    {
        MechanicalLockCem cem = MkCem();
        var sdf = new MechanicalLockShank(cem);
        float fRShank = cem.ShankDiameterMm / 2f;
        float fZGroove = cem.GrooveOffsetMm + (cem.GrooveWidthMm / 2f);

        // Inside the original surface but within the groove band ⇒ void (metal cut away).
        Assert.True(sdf.fSignedDistance(new Vector3(fRShank - 0.1f, 0f, fZGroove)) > 0f, "groove cut");
        // Below the groove floor ⇒ still solid.
        Assert.True(sdf.fSignedDistance(new Vector3(fRShank - cem.GrooveDepthMm - 0.1f, 0f, fZGroove)) < 0f, "below groove floor");
    }

    [Fact]
    public void Opposite_Direction_Mirrors_The_Lean()
    {
        var fwd = new MechanicalLockShank(MkCem(iDir: 1));
        var rev = new MechanicalLockShank(MkCem(iDir: -1));
        const float fZ0 = 2f, fPitch = 3f, fT = 0.4f;
        // Mirror about the pitch midpoint: fwd(z0+t) == rev(z0 + pitch − t).
        Assert.Equal(fwd.ProfileRadius(fZ0 + fT), rev.ProfileRadius(fZ0 + fPitch - fT), 3);
    }
}
