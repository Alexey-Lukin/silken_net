// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;

namespace SilkenCad.Tests;

// Pure-logic golden tests for the §4.3 mechanical-lock shank — CEM parse + the ratchet/groove SDF math.
// No PicoGK Library.Go (only the managed SDF), like the gyroid tests. The rendered gates (volume, barb
// count vs render, manifold) run in the `verify` CLI on a PicoGK runner.
public class MechanicalLockTests
{
    private static MechanicalLockCem MkCem() => new()
    {
        ShankDiameterMm = 11f, ShankLengthMm = 18f,
        ContactStartMm = 2f, ContactLengthMm = 12f,
        BarbRows = 4, BarbHeightMm = 0.28f, LeadAngleDeg = 30f, TrailAngleDeg = 70f,
        GrooveOffsetMm = 15f, GrooveWidthMm = 1.1f, GrooveDepthMm = 0.25f,
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

// 🔴 The physical invariant, not a sign. Walking in from local z = 0 — the end that enters the PEEK
// first — the first metal a tooth presents must rise over the LONG shallow ramp (α) and fall over the
// SHORT steep one (β): that is "easy in, hard out" (01_01 §4.3 A). This is the test the ±1 knob never
// had: `Opposite_Direction_Mirrors_The_Lean` pinned a mirror identity, so a flange built mirrored
// (steep face first into the PEEK) stayed green while its ratchet pointed the wrong way (00_07 HW.26).
// MUTATION: re-mirror the profile (fLocal = pitch − fLocal) → the rise measures β, not α → red.
internal static float FirstToothRiseLengthMm(MechanicalLockCem cem)
{
    var sdf = new MechanicalLockShank(cem);
    float fRShank = cem.ShankDiameterMm / 2f;
    const float fStep = 0.001f;
    float fZ = cem.ContactStartMm;
    float fEnd = cem.ContactStartMm + (cem.ContactLengthMm / cem.BarbRows);
    while (fZ < fEnd && sdf.ProfileRadius(fZ) <= fRShank + 1e-4f) fZ += fStep;
    float fStart = fZ;
    while (fZ < fEnd && sdf.ProfileRadius(fZ + fStep) >= sdf.ProfileRadius(fZ)) fZ += fStep;
    return fZ - fStart;   // from the first metal to the crest, measured from the insertion end
}

[Fact]
public void Shallow_Ramp_Faces_Local_Z0__The_End_That_Enters_The_Peek_First()
{
    MechanicalLockCem cem = MkCem();
    float fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);
    float fTrailLen = cem.BarbHeightMm / MathF.Tan(cem.TrailAngleDeg * MathF.PI / 180f);
    Assert.Equal(fLeadLen, FirstToothRiseLengthMm(cem), 2);
    Assert.True(FirstToothRiseLengthMm(cem) > (fLeadLen + fTrailLen) / 2f,
        "the tooth met first from the insertion end rises over the STEEP face — a reversed ratchet");
}

// Every shipped lock end — both standalone manifests AND the shank the cathode flange actually builds —
// obeys the same invariant. The flange is read through CathodeFlange.ShankCem, because that mapping is
// where the reversal lived; a manifest-only check would have stayed green over the built part.
[Fact]
public void Every_Shipped_Lock_End_Presents_Its_Shallow_Ramp_To_The_Peek_First()
{
    var ends = Cem.ManifestFiles(CemFixtures.Dir(), "mechanical_lock*.json")
        .Select(p => (Path.GetFileName(p), Cem.Parse<MechanicalLockCem>(File.ReadAllText(p))))
        .Append(("cathode_flange.json (built shank)", CathodeFlange.ShankCem(
            Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json"))))))
        .ToList();
    Assert.True(ends.Count >= 3, "the roster must include both lock manifests and the flange shank");
    foreach ((string strName, MechanicalLockCem cem) in ends)
    {
        float fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);
        float fTrailLen = cem.BarbHeightMm / MathF.Tan(cem.TrailAngleDeg * MathF.PI / 180f);
        float fRise = FirstToothRiseLengthMm(cem);
        Assert.True(fRise > (fLeadLen + fTrailLen) / 2f,
            $"{strName}: the first tooth rises over {fRise:F3} mm from the insertion end — the steep face " +
            $"(β, {fTrailLen:F3} mm) meets the PEEK first, so the ratchet is reversed (01_01 §4.3 A: easy in, hard out)");
    }
}

// A `barb_direction` key has no slot on MechanicalLockCem, so it would evaporate on parse and look
// honoured (gotcha #0b). Raw text, not the parsed record — the parser is exactly what would hide it.
[Fact]
public void No_Lock_Or_Flange_Manifest_Carries_A_Barb_Direction_Key()
{
    var files = Cem.ManifestFiles(CemFixtures.Dir(), "mechanical_lock*.json")
        .Append(Path.Combine(CemFixtures.Dir(), "cathode_flange.json")).ToList();
    Assert.True(files.Count >= 3);
    foreach (string p in files)
        Assert.False(File.ReadAllText(p).Contains("\"barb_direction\"", StringComparison.Ordinal),
            $"{Path.GetFileName(p)} carries `barb_direction`, which MechanicalLockCem has no slot for — the key " +
            "evaporates on parse; the ratchet direction is fixed by the insertion end, not by a sign");
}
}
