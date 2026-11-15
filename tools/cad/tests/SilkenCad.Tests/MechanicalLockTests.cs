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

    // A zero-width groove with a positive depth is NO groove — HasGroove is false and Build cuts nothing — so the
    // profile the verify sampler walks must not notch its closed band at z = offset either, or `verify` measures a
    // groove the part does not have. MUTATION: drop the HasGroove gate in ProfileRadius ⇒ the notch returns ⇒ red.
    [Fact]
    public void A_Zero_Width_Groove_Cuts_Nothing_From_The_Profile()
    {
        MechanicalLockCem cem = MkCem() with { GrooveWidthMm = 0f };
        Assert.False(MechanicalLock.HasGroove(cem));
        Assert.Equal(cem.ShankDiameterMm / 2f, new MechanicalLockShank(cem).ProfileRadius(cem.GrooveOffsetMm), 5);
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

// Every shipped lock end — both standalone manifests AND the shank the cathode flange actually builds. The
// flange is read through CathodeFlange.ShankCem, because that mapping is where the reversal lived; a
// manifest-only roster would have stayed green over the built part.
private static List<(string Name, MechanicalLockCem Cem)> ShippedLockEnds()
{
    var ends = Cem.ManifestFiles(CemFixtures.Dir(), "mechanical_lock*.json")
        .Select(p => (Path.GetFileName(p), Cem.Parse<MechanicalLockCem>(File.ReadAllText(p))))
        .Append(("cathode_flange.json (built shank)", CathodeFlange.ShankCem(
            Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json"))))))
        .ToList();
    Assert.True(ends.Count >= 3, "the roster must include both lock manifests and the flange shank");
    return ends;
}

// Every shipped lock end obeys the same ratchet invariant.
[Fact]
public void Every_Shipped_Lock_End_Presents_Its_Shallow_Ramp_To_The_Peek_First()
{
    foreach ((string strName, MechanicalLockCem cem) in ShippedLockEnds())
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

// ── The ridge box and the barb crests of a BUILT mesh by azimuth (MechanicalLock.RidgeBox · ReadCrestVertex ·
//    CrestFindings). Pure pins: the mesh needs the voxel runtime, which CI lacks, and no gate runs `verify` — so the
//    box pin is the only automatic red if the ridges are rendered in the bare cylinder's box again, and the crest
//    pins hold the comparison `verify` applies, never the fact that a built body passes it. ──

// The box the ridges are rendered in reaches past every crest by the band the runtime keeps round a surface — on
// both sides of X and of Y — and is no shorter than the shank along the axis.
// MUTATION: return the shank's own box ⇒ red.
[Fact]
public void The_Ridge_Box_Reaches_Past_The_Crests_On_Every_Side()
{
    MechanicalLockCem cem = MkCem();
    float fR = cem.ShankDiameterMm / 2f, fVoxel = cem.VoxelSizeMm;
    float fReach = fR + cem.BarbHeightMm + (3f * fVoxel) - 1e-4f;   // the float sum, not a looser claim
    var oShank = new PicoGK.BBox3(new Vector3(-fR, -fR, 0f), new Vector3(fR, fR, cem.ShankLengthMm));
    PicoGK.BBox3 oBox = MechanicalLock.RidgeBox(cem, oShank, fVoxel);

    Assert.True(oBox.vecMin.X <= -fReach && oBox.vecMax.X >= fReach && oBox.vecMin.Y <= -fReach && oBox.vecMax.Y >= fReach,
        $"the ridge box spans x {oBox.vecMin.X:F3}…{oBox.vecMax.X:F3}, y {oBox.vecMin.Y:F3}…{oBox.vecMax.Y:F3}; the crests " +
        $"and their band reach ±{fReach:F3} — a box short of that cuts every tooth down where it crosses the axes");
    Assert.True(oBox.vecMin.Z <= 0f && oBox.vecMax.Z >= cem.ShankLengthMm, "the ridge box is shorter than the shank");
}

// A ring of mesh vertices on every row's crest (every 0.25° of azimuth, off the sector boundaries), read through
// ReadCrestVertex: fnRadius(row, azimuth°) is the radius of the crest there.
private static float[,] CrestRing(MechanicalLockCem cem, float fVoxelMm, Func<int, float, float> fnRadius)
{
    var aCrest = new float[cem.BarbRows, MechanicalLock.CrestSectors];
    for (int nRow = 0; nRow < cem.BarbRows; nRow++)
        for (float fAz = 0.1f; fAz < 360f; fAz += 0.25f)
        {
            float fR = fnRadius(nRow, fAz), fRad = fAz * MathF.PI / 180f;
            MechanicalLock.ReadCrestVertex(cem, fVoxelMm,
                new Vector3(fR * MathF.Cos(fRad), fR * MathF.Sin(fRad), MechanicalLock.CrestZMm(cem, nRow)), aCrest);
        }
    return aCrest;
}

// The cut is given in DEGREES of the circle and read through the same vertex feed `verify` uses, so the pins hold the
// angular resolution itself:
//   • a crest whole round the circle, at the height a mesh carries it, passes;
//   • the cut the ridges had — low within 9° of an axis, on one row — is found and names the row, although the
//     largest radius round that tooth is untouched. MUTATION: CrestSectors = 12 ⇒ red (a 30° sector keeps a sound
//     vertex on either side of the cut);
//   • the declared resolution: a crest low over an arc of 6°, wherever it lies, is found. MUTATION: CrestSectors = 60
//     ⇒ red here — and only here: a 6° sector still sees the ±9° cut above, so that case alone would not hold 120;
//   • the declared ceiling: an arc of 2° between two sector centres hides behind the sound vertices either side of it;
//   • a crest standing proud of the manifest's by more than the same room is found as well, and so is a sector that
//     no vertex fed.
// MUTATION: judge a row by its largest reading instead of every sector ⇒ red · the proud side dropped ⇒ red.
[Fact]
public void A_Crest_Cut_Down_Over_An_Arc_Of_The_Circle_Is_Found_By_Its_Width_In_Degrees()
{
    MechanicalLockCem cem = MkCem();
    float fVoxel = cem.VoxelSizeMm, fNominal = (cem.ShankDiameterMm / 2f) + cem.BarbHeightMm;
    float fSound = fNominal - (0.5f * fVoxel), fCut = fNominal - (2f * fVoxel);
    static bool Within(float fAz, float fCentre, float fHalfWidth)
        => MathF.Abs(((fAz - fCentre + 540f) % 360f) - 180f) <= fHalfWidth;
    IReadOnlyList<string> Cut(int nCutRow, float fCentre, float fHalfWidth, float fRadius)
        => MechanicalLock.CrestFindings(cem, fVoxel,
            CrestRing(cem, fVoxel, (nRow, fAz) => nRow == nCutRow && Within(fAz, fCentre, fHalfWidth) ? fRadius : fSound)).Findings;

    Assert.Empty(MechanicalLock.CrestFindings(cem, fVoxel, CrestRing(cem, fVoxel, (_, _) => fSound)).Findings);

    string strAxisCut = Assert.Single(Cut(2, 90f, 9f, fCut));
    Assert.Contains("barb row 3", strAxisCut, StringComparison.Ordinal);
    Assert.Contains("the crest is LOW over", strAxisCut, StringComparison.Ordinal);

    foreach (float fCentre in new[] { 91.3f, 200.7f, 359.2f })
        Assert.Contains("barb row 2", Assert.Single(Cut(1, fCentre, 3f, fCut)), StringComparison.Ordinal);

    Assert.Empty(Cut(1, 91.5f, 1f, fCut));

    Assert.Contains("the crest stands PROUD over", Assert.Single(Cut(0, 45f, 9f, fNominal + (1.5f * fVoxel))), StringComparison.Ordinal);

    float[,] aEmpty = CrestRing(cem, fVoxel, (_, _) => fSound);
    aEmpty[0, 7] = 0f;
    Assert.Contains("barb row 1", Assert.Single(MechanicalLock.CrestFindings(cem, fVoxel, aEmpty).Findings), StringComparison.Ordinal);
}

// Where a mesh vertex (lock-local) is read: in the row whose analytic crest lies within the axial window, and in the
// sector CENTRED on its azimuth's nearest multiple of the sector width. Every point sits off a boundary, on both
// sides of what it pins: 1.2° either side of an axis must land in that axis's sector (sectors that START on the axis
// would split them), 1.8 voxels off the crest feeds and 2.2 does not.
// MUTATION: sector centres shifted by half a sector ⇒ red · CrestAxialWindowVoxels = 3 or 1 ⇒ red.
[Fact]
public void A_Mesh_Vertex_Feeds_The_Sector_Centred_On_Its_Axis_Within_Two_Voxels_Of_The_Crest()
{
    MechanicalLockCem cem = MkCem();
    float fVoxel = cem.VoxelSizeMm, fR = (cem.ShankDiameterMm / 2f) + cem.BarbHeightMm;
    float fStep = 360f / MechanicalLock.CrestSectors;
    var aCrest = new float[cem.BarbRows, MechanicalLock.CrestSectors];
    Vector3 At(float fAzimuthDeg, float fZ)
        => new(fR * MathF.Cos(fAzimuthDeg * MathF.PI / 180f), fR * MathF.Sin(fAzimuthDeg * MathF.PI / 180f), fZ);
    float fZ1 = MechanicalLock.CrestZMm(cem, 1), fZ3 = MechanicalLock.CrestZMm(cem, 3);

    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(90f - (0.4f * fStep), fZ1 + (1.8f * fVoxel)), aCrest);   // row 2, +Y, just inside the window
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(90f + (0.4f * fStep), fZ1 - (1.8f * fVoxel)), aCrest);   // … the other side of both
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(180f - (0.4f * fStep), fZ3), aCrest);                    // row 4, −X
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(180f + (0.4f * fStep), fZ3), aCrest);
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(0f, fZ1 + (2.2f * fVoxel)), aCrest);                     // just outside the window
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(0f, fZ1 - (2.2f * fVoxel)), aCrest);
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(0f, 0.5f), aCrest);                                      // plain shank
    MechanicalLock.ReadCrestVertex(cem, fVoxel, At(0f, cem.ShankLengthMm + 5f), aCrest);                    // beyond the lock

    var aFed = new List<(int Row, int Sector)>();
    for (int r = 0; r < cem.BarbRows; r++)
        for (int s = 0; s < MechanicalLock.CrestSectors; s++)
            if (aCrest[r, s] > 0f) aFed.Add((r, s));
    Assert.Equal([(1, MechanicalLock.CrestSectors / 4), (3, MechanicalLock.CrestSectors / 2)], aFed);
    Assert.Equal(fR, aCrest[1, MechanicalLock.CrestSectors / 4], 4);
}

// ── Insertion window (00_07 HW.26) — MechanicalLock.InsertionWindowMm is the arithmetic's one home ──

// The window the SHIPPED Zone-1 lock admits, from its free end: the end of its PEEK-contact zone to the end of its
// shank. ⚖️ 2026-09-18 (00_07 HW.26, «Ціна»): the deep end USED to be the near flank of the DIN-471 groove (15.0) —
// no ring is fitted as a backup any more, so the groove, still in the geometry until G3, bounds nothing. A
// regression pin on a DERIVED number read from the real manifest — it reds when the lock geometry moves, which is
// the moment any insertion judged against it has to be judged again.
// MUTATION: Min = contact_start alone · Max = groove_offset (the retired groove bound) ⇒ reds.
[Fact]
public void Zone1_Lock_Admits_Insertion_From_Its_Contact_Zone_End_To_The_End_Of_Its_Shank()
{
    var cem = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone1.json")));
    Assert.True(MechanicalLock.HasGroove(cem), "the Zone-1 groove stays in the geometry until HW.26 G3 — and bounds nothing");
    MechanicalLock.InsertionWindow w = MechanicalLock.InsertionWindowMm(cem);
    Assert.Equal(14.0f, w.MinMm, 3);   // contact_start 2 + contact_length 12
    Assert.Equal(18.0f, w.MaxMm, 3);   // shank_length 18 — NOT groove_offset 15
}

// What the window MEANS, walked on each part's own profile rather than re-derived from its fields: at any
// insertion inside it, every sample of barb metal is on the PEEK side of the mouth, and the mouth never leaves
// the shank. Lock frame, z = 0 enters first (gotcha #15): a window measured from the other end keeps plausible
// arithmetic and reds here. Roster = both lock manifests AND the shank the flange builds. ⚖️ 2026-09-18 (00_07
// HW.26): a groove is no longer a bound — no ring is fitted — so the walk asserts nothing about WHERE a groove
// sits relative to the window, only that it meets one exactly on the ends that carry one.
// MUTATION: Min = contact_start alone ⇒ a barb lies past it · Max = groove_offset ⇒ the deep end falls short of
// the shank on Zone 1 · Min/Max measured from z = shank_length ⇒ both.
[Fact]
public void Inside_Its_Window_Every_Barb_Is_In_The_Peek_And_The_Deep_End_Is_The_Whole_Shank()
{
    const float fStep = 0.005f;
    foreach ((string strName, MechanicalLockCem cem) in ShippedLockEnds())
    {
        MechanicalLock.InsertionWindow w = MechanicalLock.InsertionWindowMm(cem);
        var sdf = new MechanicalLockShank(cem);
        float fRShank = cem.ShankDiameterMm / 2f;
        int nBarb = 0, nGroove = 0;
        for (int i = 0; i * fStep <= cem.ShankLengthMm; i++)
        {
            float fZ = i * fStep;
            float fR = sdf.ProfileRadius(fZ);
            if (fR > fRShank + 1e-4f)
            {
                nBarb++;
                Assert.True(fZ <= w.MinMm,
                    $"{strName}: barb metal at z = {fZ:F3} mm lies past the window's shallow end {w.MinMm:F3} mm — " +
                    "at that insertion it is outside the sleeve");
            }
            else if (fR < fRShank - 1e-4f)
            {
                nGroove++;
            }
        }
        // The Zone-3 ends carry no groove, so there the walk must meet NONE; an end that still carries one must meet it.
        bool bGroove = MechanicalLock.HasGroove(cem);
        Assert.True(nBarb > 0 && (bGroove ? nGroove > 0 : nGroove == 0),
            $"{strName}: the walk met {nBarb} barb and {nGroove} groove samples on an end that {(bGroove ? "carries" : "carries NO")} groove");
        Assert.True(w.MinMm < w.MaxMm, $"{strName}: the window {w.MinMm:F3}–{w.MaxMm:F3} mm is empty");
        Assert.Equal(cem.ShankLengthMm, w.MaxMm, 3);
    }
}
}
