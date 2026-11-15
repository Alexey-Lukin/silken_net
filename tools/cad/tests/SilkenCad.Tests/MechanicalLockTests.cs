// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;

namespace SilkenCad.Tests;

// Pure-logic golden tests for the §4.3 mechanical-lock shank — CEM parse + the ratchet/groove SDF math.
// No PicoGK Library.Go (only the managed SDF), like the gyroid tests. The rendered gates (volume, barb
// count vs render, manifold) run in the `verify` CLI on a PicoGK runner — for the standalone lock. The INTEGRATED
// Zone-1 body has no `verify` leg: its built mesh is judged by `build --lock` itself (Program.BuildIntegrated), and
// what this file pins of it is the analytic profile, the placement map and the comparison that verb applies.
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
    => FirstToothRiseLengthMm(cem, new MechanicalLockShank(cem).ProfileRadius);

// The same walk over any body that carries the lock: `fnRadiusAtDepth` is its outer radius at a DEPTH from the end
// that enters the PEEK first. It walks the whole shank, not the first pitch: on a body built the wrong way round the
// first tooth is not where the manifest's contact zone starts, and the walk must still meet it and measure its rise.
internal static float FirstToothRiseLengthMm(MechanicalLockCem cem, Func<float, float> fnRadiusAtDepth)
{
    float fRShank = cem.ShankDiameterMm / 2f;
    const float fStep = 0.001f;
    float fZ = 0f;
    float fEnd = cem.ShankLengthMm;
    while (fZ < fEnd && fnRadiusAtDepth(fZ) <= fRShank + 1e-4f) fZ += fStep;
    float fStart = fZ;
    while (fZ < fEnd && fnRadiusAtDepth(fZ + fStep) >= fnRadiusAtDepth(fZ)) fZ += fStep;
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

// The Zone-1 lock, by file: no anchor manifest names its lock yet, so the pair is made here as `build --lock` makes it.
private static MechanicalLockCem Zone1LockCem()
    => Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone1.json")));

// Every shipped anode the Zone-1 lock integrates into — all of them (one lock for every SKU, ⚖️ founder 2026-11-15,
// 01_01 §4.3 A): the SKUs of the shank's own Ø directly, a wider one through a flat step and a neck, a narrower one
// through the shank's foot turned down. Every kind must be on the roster, or part of the pins pin nothing.
private static List<(string File, AnchorCem Cem)> IntegrableAnchors(MechanicalLockCem lockCem)
{
    var anchors = CemFixtures.AnchorFiles().Select(f => (f, CemFixtures.Anchor(f))).ToList();
    Assert.Contains(anchors, a => a.f == "anchor_zone1.pine.json");   // the pilot SKU, Ø of the shank
    Assert.Contains(anchors, a => a.Item2.OuterDiameterMm < lockCem.ShankDiameterMm);
    Assert.Contains(anchors, a => a.Item2.OuterDiameterMm > lockCem.ShankDiameterMm);
    return anchors;
}

// Every shipped lock end — both standalone manifests, the shank the cathode flange actually builds, AND the ANALYTIC
// profile of the Zone-1 shank on every anode it integrates into (Zone1Anode.IntegratedProfile). The flange is read
// through CathodeFlange.ShankCem, because that mapping is where the reversal lived; a manifest-only roster would have
// stayed green over the built part. ⛔ The integrated rows are NOT the built part: they hold the map the builder
// places by, and a BuildIntegrated that placed by another map stays green here — the built mesh is judged by
// `build --lock` (the last pins of this file hold its comparison).
// Each row carries its outer radius at a DEPTH from the end that enters the PEEK first. In a lock's own frame that
// depth is local z. On the integrated anode the sleeve arrives from above, so the depth runs DOWN from the body's top
// face, z = L + S — written here from the two manifests, never through Zone1Anode.LockLocalZ: a wrong map read back
// through itself would cancel.
private static List<(string Name, MechanicalLockCem Cem, Func<float, float> RadiusAtDepth)> ShippedLockEnds()
{
    var ends = Cem.ManifestFiles(CemFixtures.Dir(), "mechanical_lock*.json")
        .Select(p => (Path.GetFileName(p), Cem.Parse<MechanicalLockCem>(File.ReadAllText(p))))
        .Append(("cathode_flange.json (built shank)", CathodeFlange.ShankCem(
            Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json"))))))
        .Select(e => (e.Item1, e.Item2, (Func<float, float>)new MechanicalLockShank(e.Item2).ProfileRadius))
        .ToList();
    Assert.True(ends.Count >= 3, "the roster must include both lock manifests and the flange shank");

    MechanicalLockCem lockCem = Zone1LockCem();
    foreach ((string strFile, AnchorCem anode) in IntegrableAnchors(lockCem))
    {
        Func<float, float> fnProfile = Zone1Anode.IntegratedProfile(anode, lockCem);
        float fTop = anode.LengthMm + lockCem.ShankLengthMm;
        ends.Add(($"{strFile} + mechanical_lock.zone1.json (integrated anode — analytic profile, Zone1Anode.cs)", lockCem, fD => fnProfile(fTop - fD)));
    }
    return ends;
}

// Every shipped lock end obeys the same ratchet invariant.
// MUTATION (integrated rows): place the shank by a shift (Zone1Anode.LockLocalZ = z − L) ⇒ from the top face the
// first tooth rises over β ⇒ every integrated row reds, naming its SKU and Zone1Anode.cs.
[Fact]
public void Every_Shipped_Lock_End_Presents_Its_Shallow_Ramp_To_The_Peek_First()
{
    foreach ((string strName, MechanicalLockCem cem, Func<float, float> fnRadiusAtDepth) in ShippedLockEnds())
    {
        float fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);
        float fTrailLen = cem.BarbHeightMm / MathF.Tan(cem.TrailAngleDeg * MathF.PI / 180f);
        float fRise = FirstToothRiseLengthMm(cem, fnRadiusAtDepth);
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
// arithmetic and reds here. Roster = both lock manifests, the shank the flange builds AND the integrated anodes
// (depth from their top face — a shank placed by a shift leaves its last barbs past the window). ⚖️ 2026-09-18 (00_07
// HW.26): a groove is no longer a bound — no ring is fitted — so the walk asserts nothing about WHERE a groove
// sits relative to the window, only that it meets one exactly on the ends that carry one.
// MUTATION: Min = contact_start alone ⇒ a barb lies past it · Max = groove_offset ⇒ the deep end falls short of
// the shank on Zone 1 · Min/Max measured from z = shank_length ⇒ both.
[Fact]
public void Inside_Its_Window_Every_Barb_Is_In_The_Peek_And_The_Deep_End_Is_The_Whole_Shank()
{
    const float fStep = 0.005f;
    foreach ((string strName, MechanicalLockCem cem, Func<float, float> fnRadiusAtDepth) in ShippedLockEnds())
    {
        MechanicalLock.InsertionWindow w = MechanicalLock.InsertionWindowMm(cem);
        float fRShank = cem.ShankDiameterMm / 2f;
        int nBarb = 0, nGroove = 0;
        for (int i = 0; i * fStep <= cem.ShankLengthMm; i++)
        {
            float fZ = i * fStep;
            float fR = fnRadiusAtDepth(fZ);
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

// ── The Zone-1 lock integrated into the anode (00_07 HW.26 G3) — Zone1Anode.IntegratedProfile, pure maths ──

// WHERE the lock's features sit in the ANODE's frame (z = 0 at the tree-side tip), from the two manifests' numbers:
// a feature the lock manifest puts `d` from its entering end sits `d` below the anode's top face. Walked on the
// profile, not re-read from the map. The groove is the lock's own — present because the manifest's HasGroove says
// so, and gone on a copy that zeroes it: the integration adds no groove default of its own.
// MUTATION: Zone1Anode.LockLocalZ = z − L (a shift) ⇒ the groove and the barbs land at the wrong heights ⇒ red ·
// drop the groove from the integrated profile ⇒ red.
[Fact]
public void On_The_Integrated_Anode_The_Groove_And_The_Barbs_Sit_Where_The_Lock_Manifest_Puts_Them_Below_The_Top_Face()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    Assert.True(MechanicalLock.HasGroove(lockCem), "the Zone-1 lock manifest carries its groove (00_07 HW.26)");
    float fRShank = lockCem.ShankDiameterMm / 2f;
    float fPitch = lockCem.ContactLengthMm / lockCem.BarbRows;
    float fBase = lockCem.BarbHeightMm * ((1f / MathF.Tan(lockCem.LeadAngleDeg * MathF.PI / 180f))
                                          + (1f / MathF.Tan(lockCem.TrailAngleDeg * MathF.PI / 180f)));
    const float fStep = 0.001f, fTol = 2f * fStep;

    foreach ((string strFile, AnchorCem anode) in IntegrableAnchors(lockCem))
    {
        float fTop = anode.LengthMm + lockCem.ShankLengthMm;
        float fGrooveLo = fTop - (lockCem.GrooveOffsetMm + lockCem.GrooveWidthMm), fGrooveHi = fTop - lockCem.GrooveOffsetMm;
        float fContactLo = fTop - (lockCem.ContactStartMm + lockCem.ContactLengthMm), fContactHi = fTop - lockCem.ContactStartMm;
        float fLastToothFoot = fTop - (lockCem.ContactStartMm + ((lockCem.BarbRows - 1) * fPitch) + fBase);
        // The transition's span, written from the manifests (its own pins are below): the lattice is its envelope under
        // it, the lock is read above it — the neck above a flat step on a wider SKU, the turned-down foot on a narrower one.
        bool bWider = anode.OuterDiameterMm > lockCem.ShankDiameterMm;
        float fTurned = MathF.Max(0f, lockCem.ShankDiameterMm - anode.OuterDiameterMm) / 2f / MathF.Tan(Zone1Anode.TransitionHalfAngleDeg * MathF.PI / 180f);
        float fLatticeTop = bWider ? anode.LengthMm - lockCem.NeckLengthMm : anode.LengthMm, fShankFoot = anode.LengthMm + fTurned;

        Func<float, float> fnR = Zone1Anode.IntegratedProfile(anode, lockCem);
        float fGrooveMin = float.MaxValue, fGrooveMax = float.MinValue, fBarbMin = float.MaxValue, fBarbMax = float.MinValue;
        float fRMin = float.MaxValue, fRMax = float.MinValue;
        for (int i = 0; i * fStep <= fTop; i++)
        {
            float fZ = i * fStep, fR = fnR(fZ);
            if (fZ < fLatticeTop - fTol)
                Assert.True(fR == anode.OuterDiameterMm / 2f, $"{strFile}: z = {fZ:F3} mm is lattice — the profile there is its envelope, got {fR:F3}");
            if (fZ <= fShankFoot + fTol) continue;
            if (fR > fRShank + 1e-4f) { fBarbMin = MathF.Min(fBarbMin, fZ); fBarbMax = MathF.Max(fBarbMax, fZ); }
            else if (fR < fRShank - 1e-4f) { fGrooveMin = MathF.Min(fGrooveMin, fZ); fGrooveMax = MathF.Max(fGrooveMax, fZ); }
            fRMin = MathF.Min(fRMin, fR);
            fRMax = MathF.Max(fRMax, fR);
        }

        Assert.True(fGrooveMin <= fGrooveMax && fBarbMin <= fBarbMax,
            $"{strFile}: the integrated profile carries {(fGrooveMin <= fGrooveMax ? "a" : "NO")} groove and " +
            $"{(fBarbMin <= fBarbMax ? "" : "NO ")}barbs — the lock manifest declares both");
        Assert.True(MathF.Abs(fGrooveMin - fGrooveLo) <= fTol && MathF.Abs(fGrooveMax - fGrooveHi) <= fTol,
            $"{strFile}: the groove reads z {fGrooveMin:F3}…{fGrooveMax:F3} mm in the anode frame; the lock manifest puts it " +
            $"{fGrooveLo:F3}…{fGrooveHi:F3} (offset and width measured down from the top face {fTop:F3})");
        Assert.True(MathF.Abs(fBarbMax - fContactHi) <= fTol && MathF.Abs(fBarbMin - fLastToothFoot) <= fTol && fBarbMin >= fContactLo,
            $"{strFile}: barb metal reads z {fBarbMin:F3}…{fBarbMax:F3} mm in the anode frame; the lock manifest puts it " +
            $"{fLastToothFoot:F3}…{fContactHi:F3}, inside the contact zone {fContactLo:F3}…{fContactHi:F3}");
        Assert.InRange(fRMin, fRShank - lockCem.GrooveDepthMm - 1e-4f, fRShank - lockCem.GrooveDepthMm + 1e-4f);
        Assert.InRange(fRMax, fRShank + lockCem.BarbHeightMm - 0.005f, fRShank + lockCem.BarbHeightMm + 1e-4f);
        Assert.Equal(0f, fnR(-fStep));
        Assert.Equal(0f, fnR(fTop + fStep));

        Func<float, float> fnNoGroove = Zone1Anode.IntegratedProfile(anode, lockCem with { GrooveWidthMm = 0f });
        for (int i = 0; i * fStep <= fTop; i++)
            Assert.True(i * fStep <= fShankFoot + fTol || fnNoGroove(i * fStep) >= fRShank - 1e-4f,
                $"{strFile}: a lock without a groove still notches the integrated profile");
    }
}

// The placement MAP (Zone1Anode.ShankPlacement) lands the lock's entering end on the body's top face, its far end on
// the gyroid, and keeps the axis on the axis. This is the only xUnit pin of that lambda — and it is the MAP, not the
// build: that BuildIntegrated places by it is judged by `build --lock` on the mesh.
// ⛔ Rotation against mirror is deliberately NOT pinned: the shank is a body of revolution, and a mirrored placement
//    was measured to build the same body (pine + the Zone-1 lock, voxel 0.05: same triangle count, same layer profile
//    and seam, `build --lock` green).
// MUTATION: place by a shift ⇒ the entering end leaves the top face ⇒ red.
[Fact]
public void The_Integrated_Shank_Placement_Lands_The_Entering_End_On_The_Top_Face()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    AnchorCem anode = CemFixtures.Anchor("anchor_zone1.pine.json");
    Func<Vector3, Vector3> fnPlace = Zone1Anode.ShankPlacement(anode, lockCem);
    Vector3 vecEntering = fnPlace(Vector3.Zero), vecFar = fnPlace(new Vector3(0f, 0f, lockCem.ShankLengthMm));

    Assert.Equal(anode.LengthMm + lockCem.ShankLengthMm, vecEntering.Z, 4);   // where the sleeve arrives
    Assert.Equal(anode.LengthMm, vecFar.Z, 4);                                // on the gyroid's top face
    Assert.Equal(anode.LengthMm + lockCem.ShankLengthMm, Zone1Anode.IntegratedLengthMm(anode, lockCem), 4);
    foreach (Vector3 vec in new[] { vecEntering, vecFar })                    // the axis stays the axis
    {
        Assert.Equal(0f, vec.X, 5);
        Assert.Equal(0f, vec.Y, 5);
    }
}

// What is REFUSED out loud — by the placement, the profile and the build alike, before a voxel is touched: a lock with
// a channel (the cathode's — the Zone-1 shank is solid, the wire is welded on top, 01_01 §1.4); a wider anode with a lock
// that declares no neck (the step would sit at the sleeve and the part would be the depth stop, ⚖️ 2026-11-15); a
// transition long enough to cut into the lock's lowest feature (here the groove: a Ø9 anode, synthetic) or a neck that
// reaches past the lattice's tip. What is NOT refused: an anode of another Ø — every shipped SKU is accepted.
// MUTATION (run 2026-11-15, each red here): drop the channel refusal · the no-neck refusal · the lattice-tip refusal ·
// the lowest-feature refusal · bring the Ø-equality refusal back.
[Fact]
public void A_Lock_With_A_Channel__No_Neck_For_A_Wider_Anode__Or_A_Transition_That_Would_Cut_Into_The_Body_Is_Refused_And_Every_Sku_Is_Not()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    AnchorCem pine = CemFixtures.Anchor("anchor_zone1.pine.json"), oak = CemFixtures.Anchor("anchor_zone1.oak.json");
    MechanicalLockCem zone3 = Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone3.json")));
    Assert.True(zone3.BoreDiameterMm > 0f, "the Zone-3 lock carries the cathode channel — the refusal below needs it");
    Assert.True(oak.OuterDiameterMm > lockCem.ShankDiameterMm, "oak is wider than the shank — the no-neck refusal below needs it");
    // Each refusal names ITS branch and not a neighbour's — one shared message would let a test pass on the wrong branch.
    string[] aBranches = ["channel", "the part would be the depth stop", "lowest feature", "lattice's tip"];
    (string Name, AnchorCem Anode, MechanicalLockCem Lock, string Says)[] refused =
    [
        ("pine + mechanical_lock.zone3.json", pine, zone3, aBranches[0]),
        ("oak + the Zone-1 lock with no neck (synthetic)", oak, lockCem with { NeckLengthMm = 0f }, aBranches[1]),
        ("pine at Ø9 (synthetic)", pine with { OuterDiameterMm = 9f }, lockCem, aBranches[2]),
        ("pine shorter than the neck at Ø12 (synthetic)", pine with { OuterDiameterMm = 12f, LengthMm = lockCem.NeckLengthMm * 0.8f }, lockCem, aBranches[3]),
    ];
    foreach ((string strName, AnchorCem anode, MechanicalLockCem lk, string strSays) in refused)
        foreach (Action fnCall in new Action[]
                 {
                     () => Zone1Anode.ShankPlacement(anode, lk),
                     () => Zone1Anode.IntegratedProfile(anode, lk),
                     () => Zone1Anode.BuildIntegrated(anode, lk),
                 })
        {
            InvalidDataException ex = Assert.Throws<InvalidDataException>(fnCall);
            Assert.True(ex.Message.Contains(strSays, StringComparison.Ordinal), $"{strName}: the refusal must say why («{strSays}») — got «{ex.Message}»");
            foreach (string strOther in aBranches.Where(b => b != strSays))
                Assert.False(ex.Message.Contains(strOther, StringComparison.Ordinal), $"{strName}: the refusal names another branch («{strOther}») — got «{ex.Message}»");
        }

    foreach ((string strFile, AnchorCem anode) in IntegrableAnchors(lockCem))
    {
        _ = Zone1Anode.ShankPlacement(anode, lockCem);
        _ = Zone1Anode.IntegratedProfile(anode, lockCem);
    }
}

// ── The gyroid-to-shank TRANSITION (Zone1Anode.TransitionOf; ⚖️ founder 2026-11-15, clause 01_01 §4.3 A) — pure maths ──

// Every shipped SKU takes the one Zone-1 lock. A WIDER one keeps the shank's Ø as a neck g = neck_length_mm below the
// sleeve's lower end (z = L), down to a FLAT step to its own Ø — so below the sleeve the body is no wider than the bore
// for g, and from the step down it is the gyroid's; a NARROWER one meets the shank through a frustum turned on the
// shank's foot, |Δr|/tan θ long, above z = L. Nothing above z = L is wider than the lock's own profile, nothing below it
// wider than the gyroid's hole, and the body keeps L + S. Written from the two manifests' numbers; the roster carries
// every kind (IntegrableAnchors).
// ⛔ Ceiling: this is the ANALYTIC profile. The flatness BuildIntegrated actually builds is pinned by neither xUnit nor
//    CI (no voxel runtime there) — only `build --lock` reads it off the mesh (TransitionFindings, readings 1 and 4).
// MUTATION (run 2026-11-15, each red here): a cone in the ANALYTIC profile — Transition.RadiusAt interpolating on a Step,
// the builder untouched ⇒ red · the step at z = L (the neck dropped from TransitionOf) ⇒ red · the frustum on the other
// side of z = L ⇒ red · drop the transition from IntegratedProfile ⇒ red.
[Fact]
public void Every_Sku_Meets_The_One_Lock__A_Wider_One_Through_A_Flat_Step_And_A_Neck__A_Narrower_One_Through_A_Turned_Foot()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    Assert.True(lockCem.NeckLengthMm > 0f, "the Zone-1 lock declares its neck (⚖️ 2026-11-15) — without it every wider SKU is refused");
    float fRShank = lockCem.ShankDiameterMm / 2f, fTan = MathF.Tan(Zone1Anode.TransitionHalfAngleDeg * MathF.PI / 180f), fG = lockCem.NeckLengthMm;
    var oShank = new MechanicalLockShank(lockCem);
    const float fStep = 0.001f;
    foreach ((string strFile, AnchorCem anode) in IntegrableAnchors(lockCem))
    {
        float fRGyroid = anode.OuterDiameterMm / 2f, fL = anode.LengthMm, fTop = fL + lockCem.ShankLengthMm;
        Zone1Anode.Transition t = Zone1Anode.TransitionOf(anode, lockCem);
        Func<float, float> fnR = Zone1Anode.IntegratedProfile(anode, lockCem);
        Assert.Equal(fTop, Zone1Anode.IntegratedLengthMm(anode, lockCem), 4);
        Assert.Equal(t.ZBottomMm, Zone1Anode.SeamZMm(anode, lockCem));
        if (fRGyroid == fRShank)
        {
            Assert.True(t.None, $"{strFile}: an anode of the shank's Ø needs no transition");
            continue;
        }

        bool bWider = fRGyroid > fRShank;
        float fZ0 = bWider ? fL - fG : fL, fZ1 = bWider ? fL : fL + ((fRShank - fRGyroid) / fTan);
        Assert.Equal(bWider, t.Step);
        Assert.Equal(fRGyroid, t.RBottomMm);
        Assert.Equal(fRShank, t.RTopMm);
        Assert.Equal(fZ0, t.ZBottomMm, 4);
        Assert.Equal(fZ1, t.ZTopMm, 3);

        for (int i = 0; i * fStep <= fTop; i++)
        {
            float fZ = i * fStep, fR = fnR(fZ);
            if (fZ >= fL) Assert.True(fR <= oShank.ProfileRadius(fTop - fZ) + 1e-4f,
                $"{strFile}: z = {fZ:F3} sits in the sleeve and stands out to r {fR:F3}, past the lock's own profile");
            else Assert.True(fR <= fRGyroid + 1e-4f, $"{strFile}: z = {fZ:F3} stands out to r {fR:F3}, past the gyroid's own hole");
            if (fZ < fZ0 - 1e-4f || fZ > fZ1 + 1e-4f || (bWider && fZ <= fZ0 + 1e-4f)) continue;   // lattice · lock · the step's own plane
            float fWant = bWider ? fRShank : fRGyroid + ((fRShank - fRGyroid) * (fZ - fZ0) / (fZ1 - fZ0));
            Assert.True(MathF.Abs(fR - fWant) < 1e-3f, $"{strFile}: z = {fZ:F3} reads r {fR:F4}, the {(bWider ? "neck" : "frustum")} asks {fWant:F4}");
        }
        // The stop that follows, without a judgment: below the sleeve's lower end the body is no wider than the bore for g
        // on a wider SKU, and then the gyroid's Ø at once; on a narrower one it is never wider.
        if (bWider)
        {
            Assert.True(fnR(fZ0 + 0.01f) <= fRShank + 1e-4f, $"{strFile}: just above the step the neck reads r {fnR(fZ0 + 0.01f):F3}, wider than the bore");
            Assert.True(fnR(fZ0 - 0.01f) == fRGyroid, $"{strFile}: just below the step the body reads r {fnR(fZ0 - 0.01f):F3} — the step is not flat");
        }
        else Assert.True(fnR(fL - 0.05f) < fRShank, $"{strFile}: 0.05 mm below the sleeve's lower end the body reads r {fnR(fL - 0.05f):F3}, not inside the bore");
    }
}

// The frustum's face stands in a vertical print whichever end is down (G4's first reading, 01_02 §1.6 — the second, a
// bureau's own orientation, is not judged): the half-angle leaves it, at the full tilt 01_02 §1.6 admits, at least as
// steep as the one face canon calls self-supporting (01_01 §4.3 A) — and the two canon numbers the rule is made of are
// the ones those sections give.
// MUTATION (run 2026-11-15, each red here): TransitionHalfAngleDeg = 26 · the datum 60 → 55 · the tilt 5 → 4.
[Fact]
public void The_Transition_Face_Is_As_Steep_As_The_Canon_Self_Supporting_Face_At_The_Full_Tilt()
{
    Assert.Equal(60f, Zone1Anode.SelfSupportingFaceFromHorizontalDeg);   // 01_01 §4.3 A: «downward-грань ≈ 60° від горизонталі»
    Assert.Equal(5f, Zone1Anode.BuildTiltToleranceDeg);                  // 01_02 §1.6: «0° (вертикальний) ± 5°»
    float fWorstFace = 90f - Zone1Anode.TransitionHalfAngleDeg - Zone1Anode.BuildTiltToleranceDeg;
    Assert.True(fWorstFace >= Zone1Anode.SelfSupportingFaceFromHorizontalDeg,
        $"the transition face sits {fWorstFace:F1}° from horizontal at the full tilt — flatter than the {Zone1Anode.SelfSupportingFaceFromHorizontalDeg}° face canon calls self-supporting");
}

// The per-layer reading `build --lock` takes round the transition — each layer's largest and smallest radius of any
// vertex — made HERE from radius profiles written from the manifests' numbers, never through Zone1Anode, over the window
// the verb reads. A solid body has vertices on its outer surface only, so its smallest radius is the profile's; fnInner
// puts a surface inside it (lattice, a void) where that is the case under test.
private static (float[] Max, float[] Min) TransitionReading(AnchorCem anode, MechanicalLockCem lockCem, Func<float, float> fnR,
                                                            Func<float, float>? fnInner = null)
{
    float fLayer = lockCem.VoxelSizeMm;
    Zone1Anode.Transition t = Zone1Anode.TransitionOf(anode, lockCem);   // the window only
    float fFoot = Zone1Anode.TransitionWindowFootMm(t, fLayer);
    int n = Zone1Anode.TransitionLayerCount(t, fLayer);
    float[] aMax = new float[n], aMin = new float[n];
    Array.Fill(aMin, float.MaxValue);
    for (int j = 0; j < n; j++)
        for (int i = 0; i <= 20; i++)
        {
            float fZ = fFoot + ((j + (i / 20f)) * fLayer);
            aMax[j] = MathF.Max(aMax[j], fnR(fZ));
            aMin[j] = MathF.Min(aMin[j], (fnInner ?? fnR)(fZ));
        }
    return (aMax, aMin);
}

private static (string Summary, IReadOnlyList<string> Findings) TransitionCheck(AnchorCem anode, MechanicalLockCem lockCem,
                                                                                (float[] Max, float[] Min) reading)
    => Zone1Anode.TransitionFindings(anode, lockCem, lockCem.VoxelSizeMm, reading.Max, reading.Min);

private static IReadOnlyList<string> NoMeshFindings(AnchorCem anode, MechanicalLockCem lockCem)
{
    int n = Zone1Anode.TransitionLayerCount(Zone1Anode.TransitionOf(anode, lockCem), lockCem.VoxelSizeMm);
    return TransitionCheck(anode, lockCem, (new float[n], new float[n])).Findings;
}

// A frustum from the gyroid's radius to the shank's at the given half-angle, on the shank's side of z = L on a narrower
// SKU and below it on a wider one (there: the cone 2026-11-15 rejected).
private static Func<float, float> FrustumProfile(AnchorCem anode, MechanicalLockCem lockCem, float fHalfAngleDeg, float fScale = 1f)
{
    float fRGyroid = anode.OuterDiameterMm / 2f, fRShank = lockCem.ShankDiameterMm / 2f, fL = anode.LengthMm;
    float fLen = MathF.Abs(fRShank - fRGyroid) / MathF.Tan(fHalfAngleDeg * MathF.PI / 180f);
    float fZ0 = fRGyroid > fRShank ? fL - fLen : fL, fZ1 = fZ0 + fLen;
    return fZ => fZ <= fZ0 ? fRGyroid : fZ >= fZ1 ? fRShank : fScale * (fRGyroid + ((fRShank - fRGyroid) * (fZ - fZ0) / fLen));
}

// A flat step from the gyroid's radius to the neck at fGMm below z = L, the shank's radius above.
private static Func<float, float> FlatStepProfile(AnchorCem anode, MechanicalLockCem lockCem, float fGMm, float fNeckScale = 1f)
{
    float fRGyroid = anode.OuterDiameterMm / 2f, fRShank = lockCem.ShankDiameterMm / 2f, fL = anode.LengthMm;
    return fZ => fZ <= fL - fGMm ? fRGyroid : fZ < fL ? fNeckScale * fRShank : fRShank;
}

// What `build --lock` reads round the turned-down foot (broadleaf): the shipped frustum passes, its angle reads back and
// its face is down-facing with the tip down; a frustum flatter than the tolerance lets through reds on the ANGLE alone;
// a frustum cut in, a hollow one, a body wider than the bore below the sleeve (the part as the depth stop) and a body with
// holes are each named; no stop is the summary.
// The angle row is the declared ceiling of TransitionAngleToleranceDeg: 25.9° passes, 26.5° reds.
// MUTATION (run 2026-11-15, each red here): the angle comparison dropped · the cut-in finding dropped · the solidity
// finding dropped · the stop on a frustum not a finding.
[Fact]
public void The_Transition_Check_Passes_The_Turned_Foot_And_Names_What_Left_It()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    AnchorCem broadleaf = CemFixtures.Anchor("anchor_zone1.broadleaf.json");
    Assert.True(broadleaf.OuterDiameterMm < lockCem.ShankDiameterMm, "broadleaf is narrower than the shank — the frustum rows need it");
    float fRShank = lockCem.ShankDiameterMm / 2f, fTheta = Zone1Anode.TransitionHalfAngleDeg;
    (string Summary, IReadOnlyList<string> Findings) Check(Func<float, float> fnR, Func<float, float>? fnInner = null)
        => TransitionCheck(broadleaf, lockCem, TransitionReading(broadleaf, lockCem, fnR, fnInner));

    (string strSummary, IReadOnlyList<string> aGood) = Check(FrustumProfile(broadleaf, lockCem, fTheta));
    Assert.Empty(aGood);
    Assert.Contains($"half-angle {fTheta:F2}°", strSummary, StringComparison.Ordinal);
    Assert.Contains("DOWN-facing with the tip down", strSummary, StringComparison.Ordinal);
    Assert.Contains("no stop in the part", strSummary, StringComparison.Ordinal);
    Assert.Empty(Check(FrustumProfile(broadleaf, lockCem, 25.9f)).Findings);
    Assert.Contains("flatter than the 60° face", Assert.Single(Check(FrustumProfile(broadleaf, lockCem, 26.5f)).Findings), StringComparison.Ordinal);
    AssertFinds(Check(FrustumProfile(broadleaf, lockCem, 35f)).Findings, "flatter than the 60° face");
    AssertFinds(Check(FrustumProfile(broadleaf, lockCem, fTheta, fScale: 0.97f)).Findings, "the transition reaches only");
    Func<float, float> fnFrustum = FrustumProfile(broadleaf, lockCem, fTheta);
    AssertFinds(Check(fZ => fZ < broadleaf.LengthMm ? fRShank + 0.1f : fnFrustum(fZ)).Findings, "the part would stop the depth");
    Assert.Contains("is not solid", Assert.Single(Check(fnFrustum, fnInner: _ => 1f).Findings), StringComparison.Ordinal);
    Assert.Contains("carry NO mesh", Assert.Single(NoMeshFindings(broadleaf, lockCem)), StringComparison.Ordinal);
}

// What `build --lock` reads round the FLAT step (oak · tropical): the shipped step at the lock's neck g passes, its
// clearance reads back as a one-layer bracket holding g, and the summary says the press fixture is the stop; the
// rejected 25° cone and a step AT the sleeve red on the clearance and on metal out of the profile; a step too high reds
// on the clearance; a step too LOW and a missing step red on the clearance alone — nothing else reads them; a neck cut
// in, a neck left as lattice (the solidity reading alone — it touches r 5.5 on every layer) and a body with holes are
// each named.
// The clearance rows are the declared ceiling of the step reading — two layers of axial tolerance beyond a bracket one
// layer wide: a step g + 2 layers down passes, g + 4 layers reds, and between them the reading's own layer boundary
// decides (whether a sample lands ON the step's plane is float arithmetic), so no row is pinned there.
// MUTATION (run 2026-11-15, each red here): drop reading 4's comparison · a step SKU with no step found left without a
// finding · drop the solidity finding · drop the cut-in finding · the voxel floor (LayerReadsTransition) made always true.
[Fact]
public void The_Transition_Check_Passes_The_Flat_Step_And_Names_What_Left_It()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    float fLayer = lockCem.VoxelSizeMm, fG = lockCem.NeckLengthMm;
    foreach (string strFile in new[] { "anchor_zone1.oak.json", "anchor_zone1.tropical.json" })
    {
        AnchorCem anode = CemFixtures.Anchor(strFile);
        Assert.True(anode.OuterDiameterMm > lockCem.ShankDiameterMm, $"{strFile} is wider than the shank — the step rows need it");
        // The voxel floor of the reading (`build --lock` refuses below it, exit 2): the shipped neck clears it, one of six
        // layers does not.
        Assert.True(Zone1Anode.LayerReadsTransition(Zone1Anode.TransitionOf(anode, lockCem), fLayer), $"{strFile}: the shipped neck is below the reading's floor");
        Assert.False(Zone1Anode.LayerReadsTransition(Zone1Anode.TransitionOf(anode, lockCem with { NeckLengthMm = 6 * fLayer }), fLayer),
            $"{strFile}: a neck of six layers passed the reading's floor of seven");
        (string Summary, IReadOnlyList<string> Findings) Check(Func<float, float> fnR, Func<float, float>? fnInner = null)
            => TransitionCheck(anode, lockCem, TransitionReading(anode, lockCem, fnR, fnInner));
        IReadOnlyList<string> Step(float fGMm, float fNeckScale = 1f) => Check(FlatStepProfile(anode, lockCem, fGMm, fNeckScale)).Findings;

        (string strSummary, IReadOnlyList<string> aGood) = Check(FlatStepProfile(anode, lockCem, fG));
        Assert.Empty(aGood);
        Assert.Contains("a FLAT step", strSummary, StringComparison.Ordinal);
        Assert.Contains("stop by the press fixture; the step clears the sleeve end by g = ", strSummary, StringComparison.Ordinal);
        Assert.True(strSummary.Contains($"…{fG:F2} mm", StringComparison.Ordinal) || strSummary.Contains($"g = {fG:F2}…", StringComparison.Ordinal),
            $"{strFile}: the clearance bracket must hold the manifest's g {fG:F2} — got «{strSummary}»");

        IReadOnlyList<string> aCone = Check(FrustumProfile(anode, lockCem, Zone1Anode.TransitionHalfAngleDeg)).Findings;
        AssertFinds(aCone, "the step clears");
        AssertFinds(aCone, "metal out to r");
        AssertFinds(Step(0f), "the step clears");
        AssertFinds(Step(0f), "metal out to r");
        AssertFinds(Step(fG - (4 * fLayer)), "the step clears");
        Assert.Empty(Step(fG + (2 * fLayer)));
        Assert.Contains("the step clears", Assert.Single(Step(fG + (4 * fLayer))), StringComparison.Ordinal);
        Assert.Contains("the step to Ø", Assert.Single(Step(anode.LengthMm + 1f)), StringComparison.Ordinal);
        AssertFinds(Step(fG, fNeckScale: 0.97f), "the transition reaches only");
        // The neck left as the lattice clipped to Ø11: every layer still touches r 5.5, only a surface inside it tells.
        Assert.Contains("is not solid", Assert.Single(Check(FlatStepProfile(anode, lockCem, fG), fnInner: _ => 0.3f).Findings), StringComparison.Ordinal);
        Assert.Contains("carry NO mesh", Assert.Single(NoMeshFindings(anode, lockCem)), StringComparison.Ordinal);
    }
}

// On a SKU whose neck replaced lattice the seam plane is the STEP: a lattice crumb under it passes, a surface between it
// and z = L — inside what is solid neck now — reds.
// MUTATION (run 2026-11-15, red here): SeamZMm returns z = L.
[Fact]
public void Where_The_Neck_Replaced_Lattice_The_Seam_Plane_Is_The_Step()
{
    MechanicalLockCem lockCem = Zone1LockCem();
    AnchorCem oak = CemFixtures.Anchor("anchor_zone1.oak.json");
    float fL = oak.LengthMm, fTop = fL + lockCem.ShankLengthMm, fFoot = Zone1Anode.TransitionOf(oak, lockCem).ZBottomMm, fLayer = 0.05f;
    Assert.True(fFoot < fL - (4f * fLayer), "oak's step must sit below z = L for this pin to judge anything");
    static (float[] Z, int[] T) Strip(params float[] aZ)
        => (aZ, [.. Enumerable.Range(0, aZ.Length - 2).SelectMany(i => new[] { i, i + 1, i + 2 })]);
    static (float[] Z, int[] T) Join((float[] Z, int[] T) a, (float[] Z, int[] T) b)
        => ([.. a.Z, .. b.Z], [.. a.T, .. b.T.Select(i => i + a.Z.Length)]);
    IReadOnlyList<string> Findings((float[] Z, int[] T) m) => Zone1Anode.IntegratedSeamFindings(oak, lockCem, fLayer, m.Z, m.T).Findings;

    (float[] Z, int[] T) body = Strip(0f, fFoot, fL, fL + 1f, fTop);
    Assert.Empty(Findings(Join(body, Strip(fFoot - 0.09f, fFoot - 0.06f, fFoot - 0.03f))));
    AssertFinds(Findings(Join(body, Strip(fFoot + 0.2f, fFoot + 0.25f, fFoot + 0.3f))), "rise above the seam plane");
}

// ── The comparison `build --lock` applies to the mesh it is about to write (Zone1Anode.IntegratedProfileFindings ·
//    IntegratedSeamFindings). Pinned on SYNTHETIC inputs — why, and what that leaves unguarded, is in the header of
//    Zone1Anode.BuildIntegrated: these pins hold the comparison, never the fact that the verb applies it. ──

// A lock's outer radius at a DEPTH below the top face, written out from the manifest's numbers — deliberately NOT
// through Zone1Anode or MechanicalLockShank, so a "mesh" made of it is independent of the profile under test.
// nMirroredRow turns one barb row round (steep face first); nScaledRow makes one row fScale of its size (same
// angles). Rows are 0-based from the top face.
private static float LockRadiusAtDepth(MechanicalLockCem c, float fDepth, int nMirroredRow = -1, int nScaledRow = -1, float fScale = 1f)
{
    float fR = c.ShankDiameterMm / 2f, fPitch = c.ContactLengthMm / c.BarbRows;
    float fT = fDepth - c.ContactStartMm;
    if (fT >= 0f && fT <= c.ContactLengthMm)
    {
        int nRow = Math.Min((int)(fT / fPitch), c.BarbRows - 1);
        float fH = c.BarbHeightMm * (nRow == nScaledRow ? fScale : 1f);
        float fLead = fH / MathF.Tan(c.LeadAngleDeg * MathF.PI / 180f), fTrail = fH / MathF.Tan(c.TrailAngleDeg * MathF.PI / 180f);
        float fIn = fT - (nRow * fPitch);
        if (nRow == nMirroredRow) fIn = fLead + fTrail - fIn;
        if (fIn >= 0f && fIn < fLead) fR += fH * fIn / fLead;
        else if (fIn >= fLead && fIn < fLead + fTrail) fR += fH * (1f - ((fIn - fLead) / fTrail));
    }
    if (c.GrooveWidthMm > 0f && c.GrooveDepthMm > 0f && fDepth >= c.GrooveOffsetMm && fDepth <= c.GrooveOffsetMm + c.GrooveWidthMm)
        fR -= c.GrooveDepthMm;
    return fR;
}

// What `build --lock` reads off a mesh: per layer the largest and the smallest radius, per barb row the crest in every
// sector of the circle.
private sealed record MeshReading(float[] Max, float[] Min, float[,] Crest)
{
    public MeshReading With(Func<float, float> fnRadius)
    {
        var aCrest = (float[,])Crest.Clone();
        for (int r = 0; r < aCrest.GetLength(0); r++)
            for (int s = 0; s < aCrest.GetLength(1); s++) aCrest[r, s] = fnRadius(aCrest[r, s]);
        return new([.. Max.Select(fnRadius)], [.. Min.Select(fnRadius)], aCrest);
    }
}

// The shipped pair and the layer `build --lock` reads it at, plus the shorthands the pins below share: the reading a
// mesh of a body of revolution gives — sampled HERE, not by the check — and what the check finds on a reading. The
// body is the SHIPPED lock unless another is handed in; the crests are read where the SHIPPED lock's manifest puts
// them (start + row·pitch + lead run, ± the check's two layers), the same in every sector.
private sealed record MeshCheck(AnchorCem Anode, MechanicalLockCem Lock, float LayerMm)
{
    public static MeshCheck Shipped()
    {
        AnchorCem anode = CemFixtures.Anchor("anchor_zone1.pine.json");
        MechanicalLockCem lockCem = Zone1LockCem();
        return new(anode, lockCem, MathF.Min(anode.VoxelSizeMm, lockCem.VoxelSizeMm));
    }

    public MeshReading Read(Func<float, float> fnRadiusAtDepth)
    {
        float fLayer = LayerMm;
        int n = (int)MathF.Round(Lock.ShankLengthMm / fLayer);
        float[] aMax = new float[n], aMin = new float[n];
        for (int j = 0; j < n; j++)
        {
            (aMax[j], aMin[j]) = (float.MinValue, float.MaxValue);
            for (int i = 0; i <= 20; i++)
            {
                float fR = fnRadiusAtDepth((j + (i / 20f)) * fLayer);
                (aMax[j], aMin[j]) = (MathF.Max(aMax[j], fR), MathF.Min(aMin[j], fR));
            }
        }
        var aCrest = new float[Lock.BarbRows, MechanicalLock.CrestSectors];
        float fLead = Lock.BarbHeightMm / MathF.Tan(Lock.LeadAngleDeg * MathF.PI / 180f);
        for (int r = 0; r < Lock.BarbRows; r++)
        {
            float fAt = Lock.ContactStartMm + (r * Lock.ContactLengthMm / Lock.BarbRows) + fLead, fCrest = float.MinValue;
            for (int i = -40; i <= 40; i++) fCrest = MathF.Max(fCrest, fnRadiusAtDepth(fAt + (i / 40f * 2f * fLayer)));
            for (int s = 0; s < MechanicalLock.CrestSectors; s++) aCrest[r, s] = fCrest;
        }
        return new(aMax, aMin, aCrest);
    }

    public MeshReading Mesh(MechanicalLockCem? built = null, int nMirroredRow = -1, int nScaledRow = -1, float fScale = 1f)
        => Read(fD => LockRadiusAtDepth(built ?? Lock, fD, nMirroredRow, nScaledRow, fScale));

    public IReadOnlyList<string> Findings(MeshReading mesh, MechanicalLockCem? declared = null)
        => Zone1Anode.IntegratedProfileFindings(Anode, declared ?? Lock, LayerMm, mesh.Max, mesh.Min, mesh.Crest).Findings;
}

private static void AssertFinds(IReadOnlyList<string> aFindings, string strPart, string? strNot = null)
{
    Assert.True(aFindings.Any(f => f.Contains(strPart, StringComparison.Ordinal)),
        $"expected a finding with «{strPart}», got: {(aFindings.Count == 0 ? "none" : string.Join(" | ", aFindings))}");
    if (strNot is not null)
        Assert.False(aFindings.Any(f => f.Contains(strNot, StringComparison.Ordinal)),
            $"a finding names «{strNot}», which is not what was wrong: {string.Join(" | ", aFindings)}");
}

// The shank the two manifests describe passes — on a reading made in THIS file from the manifest's numbers, also the
// way a real mesh carries it (every face one layer off either way, every radius half a voxel short) — and each fault
// is NAMED by where it sits: a shank placed by a shift is a reversed ratchet; a lost row, an extra row, a row turned
// round behind a correct first one, a lost groove, a groove nobody declared, low teeth, a tooth low on PART of the
// circle and an ovalised section each leave IntegratedProfile at their own place, and none is called a ratchet
// fault. A body with no shank at all — or with layers that carry no mesh — is said to be exactly that, and nothing
// else is read off it.
// MUTATION: the rise-against-fall comparison dropped ⇒ red · the every-layer findings not added ⇒ red · the crest
// findings not added ⇒ red · the empty-layer finding dropped ⇒ red.
[Fact]
public void The_Mesh_Check_Passes_The_Shank_The_Manifests_Describe_And_Names_What_Left_It()
{
    MeshCheck c = MeshCheck.Shipped();
    MeshReading good = c.Mesh();

    Assert.Empty(c.Findings(good));
    Assert.Empty(c.Findings(good with { Max = [.. good.Max.Skip(1), good.Max[^1]], Min = [.. good.Min.Skip(1), good.Min[^1]] }));
    Assert.Empty(c.Findings(good with { Max = [good.Max[0], .. good.Max.SkipLast(1)], Min = [good.Min[0], .. good.Min.SkipLast(1)] }));
    float fCap = good.Max.Max() - (0.5f * c.LayerMm);
    Assert.Empty(c.Findings(good.With(r => MathF.Min(r, fCap))));

    // The lock un-turned: what a shift instead of the turn puts under the top face.
    AssertFinds(c.Findings(c.Read(fD => LockRadiusAtDepth(c.Lock, c.Lock.ShankLengthMm - fD))), "ratchet is REVERSED");

    AssertFinds(c.Findings(c.Mesh(c.Lock with { BarbRows = 3, ContactLengthMm = 9f })), "leaves IntegratedProfile at barb row 4", "REVERSED");
    AssertFinds(c.Findings(c.Mesh(c.Lock with { BarbRows = 5, ContactLengthMm = 15f })), "leaves IntegratedProfile at the plain shank", "REVERSED");
    AssertFinds(c.Findings(c.Mesh(nMirroredRow: 1)), "leaves IntegratedProfile at barb row 2", "REVERSED");
    AssertFinds(c.Findings(c.Mesh(c.Lock with { GrooveWidthMm = 0f })), "leaves IntegratedProfile at the groove band", "REVERSED");
    AssertFinds(c.Findings(good, declared: c.Lock with { GrooveWidthMm = 0f }), "leaves IntegratedProfile at the plain shank", "REVERSED");
    AssertFinds(c.Findings(c.Mesh(c.Lock with { BarbHeightMm = 0.6f * c.Lock.BarbHeightMm })), "the crest is LOW over", "REVERSED");
    AssertFinds(c.Findings(good with { Min = [.. good.Min.Select(r => 0.9f * r)] }), "metal only to r", "REVERSED");
    AssertFinds(c.Findings(c.Mesh(c.Lock with { BarbRows = 1, BarbHeightMm = 0f })), "NO barb");

    // A tooth low on part of the circle: both layer extremes read exactly as on the good mesh — only the crest read
    // by azimuth shows it.
    var aCutCrest = (float[,])good.Crest.Clone();
    for (int s = 0; s < 20; s++) aCutCrest[1, s] -= 2f * c.LayerMm;
    IReadOnlyList<string> aCut = c.Findings(good with { Crest = aCutCrest });
    AssertFinds(aCut, $"leaves IntegratedProfile at barb row 2: the crest is LOW over 20 of {MechanicalLock.CrestSectors} sectors", "REVERSED");
    Assert.Single(aCut);

    // No shank, or holes in it: said so, once, and never as a ratchet fault.
    Assert.Contains("carry NO mesh at all", Assert.Single(c.Findings(good.With(_ => 0f))), StringComparison.Ordinal);
    float[] aHoled = [.. good.Max];
    aHoled[100] = aHoled[101] = aHoled[102] = 0f;
    Assert.Contains("3 of the", Assert.Single(c.Findings(good with { Max = aHoled })), StringComparison.Ordinal);

    // A layer too coarse to tell α from β is never judged: Program asks this predicate and refuses before it builds.
    Assert.True(Zone1Anode.LayerResolvesRatchet(c.Lock, c.LayerMm));
    Assert.False(Zone1Anode.LayerResolvesRatchet(c.Lock, 0.1f));
}

// The CEILINGS of that check, as a table of pins — the one home of these numbers. Each row is a departure at the last
// scanned value that still PASSES, beside the next scanned value, which REDS: the edge of what the tolerances let
// through lies between the two. Ideal synthetic readings of the shipped lock at its voxel (0.05 mm) — a real mesh
// spends part of each tolerance on its own rounding, so on a build the edges are nearer, never farther. The scan
// grids sit off the round numbers on purpose (0.049 / 0.051, not 0.05), so no row stands on a float tie.
// What the table says, in words: a radius may be off by a voxel (crest, tooth height, groove depth, shank radius, a
// layer's smallest radius by under 1 %), a face by under two voxels along the axis (groove position and width, the
// barb rows) — and with the faces the flank ANGLES, which are judged only by where a flank's foot lands.
// ⛔ What no reading here can show at all, at any size:
//    • a tooth's FLANK cut down on part of the circle below its crest — next to the steep face the smallest radius
//      of a tooth layer is held only to the plain shank's;
//    • a crest low over an arc of under 6° that straddles two 3° sectors and leaves each a sound vertex (an arc of
//      6° or more is found wherever it lies — the lock's own pin);
//    • everything on the lattice below the seam, anything wholly below the seam plane, and a membrane inside the
//      metal that shares its vertices with the outer surface (IntegratedSeamFindings).
[Fact]
public void The_Mesh_Check_Lets_Through_What_Its_Tolerances_Declare()
{
    MeshCheck c = MeshCheck.Shipped();
    MechanicalLockCem k = c.Lock;
    MeshReading good = c.Mesh();
    MeshReading CrestShort(float fBy)
    {
        float fCap = good.Max.Max() - fBy;
        return good.With(r => MathF.Min(r, fCap));
    }
    MeshReading SectorsShort(float fBy)
    {
        var aCrest = (float[,])good.Crest.Clone();
        for (int s = 0; s < 20; s++) aCrest[1, s] -= fBy;
        return good with { Crest = aCrest };
    }
    MeshReading SmallestScaled(float fScale) => good with { Min = [.. good.Min.Select(r => fScale * r)] };
    MeshReading Height(float fScale) => c.Mesh(k with { BarbHeightMm = fScale * k.BarbHeightMm });
    MeshReading GrooveAt(float fShift) => c.Mesh(k with { GrooveOffsetMm = k.GrooveOffsetMm + fShift });
    MeshReading ShankRadius(float fBy) => c.Mesh(k with { ShankDiameterMm = k.ShankDiameterMm + (2f * fBy) });
    MeshReading RowsAt(float fShift) => c.Mesh(k with { ContactStartMm = k.ContactStartMm + fShift });

    (string What, MeshReading Passes, MeshReading Reds)[] aRows =
    [
        ("every crest short by 0.049 / 0.051 mm", CrestShort(0.049f), CrestShort(0.051f)),
        ("a crest short over 20 sectors by 0.049 / 0.051 mm", SectorsShort(0.049f), SectorsShort(0.051f)),
        ("one tooth at 0.885 / 0.875 of its size", c.Mesh(nScaledRow: 1, fScale: 0.885f), c.Mesh(nScaledRow: 1, fScale: 0.875f)),
        ("one tooth at 1.175 / 1.185 of its size", c.Mesh(nScaledRow: 1, fScale: 1.175f), c.Mesh(nScaledRow: 1, fScale: 1.185f)),
        ("every tooth at 0.885 / 0.875 of its height", Height(0.885f), Height(0.875f)),
        ("every tooth at 1.175 / 1.185 of its height", Height(1.175f), Height(1.185f)),
        ("β 47.5° / 46.5° for 70°", c.Mesh(k with { TrailAngleDeg = 47.5f }), c.Mesh(k with { TrailAngleDeg = 46.5f })),
        ("β 85.5° / 86.5° for 70°", c.Mesh(k with { TrailAngleDeg = 85.5f }), c.Mesh(k with { TrailAngleDeg = 86.5f })),
        ("α 25.25° / 24.75° for 30°", c.Mesh(k with { LeadAngleDeg = 25.25f }), c.Mesh(k with { LeadAngleDeg = 24.75f })),
        ("α 33.75° / 34.25° for 30°", c.Mesh(k with { LeadAngleDeg = 33.75f }), c.Mesh(k with { LeadAngleDeg = 34.25f })),
        ("groove 0.201 / 0.199 deep for 0.25", c.Mesh(k with { GrooveDepthMm = 0.201f }), c.Mesh(k with { GrooveDepthMm = 0.199f })),
        ("groove 0.299 / 0.301 deep for 0.25", c.Mesh(k with { GrooveDepthMm = 0.299f }), c.Mesh(k with { GrooveDepthMm = 0.301f })),
        ("groove shifted −0.0975 / −0.1025", GrooveAt(-0.0975f), GrooveAt(-0.1025f)),
        ("groove shifted +0.0975 / +0.1025", GrooveAt(0.0975f), GrooveAt(0.1025f)),
        ("groove 1.0025 / 0.9975 wide for 1.1", c.Mesh(k with { GrooveWidthMm = 1.0025f }), c.Mesh(k with { GrooveWidthMm = 0.9975f })),
        ("groove 1.1975 / 1.2025 wide for 1.1", c.Mesh(k with { GrooveWidthMm = 1.1975f }), c.Mesh(k with { GrooveWidthMm = 1.2025f })),
        ("shank radius −0.049 / −0.051", ShankRadius(-0.049f), ShankRadius(-0.051f)),
        ("shank radius +0.049 / +0.051", ShankRadius(0.049f), ShankRadius(0.051f)),
        ("a layer's smallest radius at 0.9915 / 0.9905 of nominal", SmallestScaled(0.9915f), SmallestScaled(0.9905f)),
        ("barb rows shifted −0.0675 / −0.0725", RowsAt(-0.0675f), RowsAt(-0.0725f)),
        ("barb rows shifted +0.1175 / +0.1225", RowsAt(0.1175f), RowsAt(0.1225f)),
    ];
    foreach ((string strWhat, MeshReading passes, MeshReading reds) in aRows)
    {
        IReadOnlyList<string> aPass = c.Findings(passes), aRed = c.Findings(reds);
        Assert.True(aPass.Count == 0, $"{strWhat}: the first value is inside the declared tolerance — got {string.Join(" | ", aPass)}");
        Assert.True(aRed.Count > 0, $"{strWhat}: the second value passed");
        // An evenly thick or thin shank is a radius finding, never a ratchet one.
        Assert.DoesNotContain(aRed, f => strWhat.StartsWith("shank radius", StringComparison.Ordinal) && f.Contains("REVERSED", StringComparison.Ordinal));
    }
}

// How `build --lock` reads a mesh vertex into the layers: inside a layer it feeds that layer, on a layer boundary BOTH
// neighbours, below the junction nothing. The boundary rule is not cosmetic: voxel planes fall on the layer boundaries
// when the anode's length is half a voxel off the grid, and a real build at L = 40.025 came back with empty layers
// — a red for nothing — before it.
// MUTATION: the both-layers rule dropped ⇒ red.
[Fact]
public void A_Mesh_Vertex_On_A_Layer_Boundary_Feeds_Both_Layers()
{
    MeshCheck c = MeshCheck.Shipped();
    float fTop = c.Anode.LengthMm + c.Lock.ShankLengthMm;
    int n = Zone1Anode.ShankLayerCount(c.Lock, c.LayerMm);
    float[] aMax = new float[n], aMin = new float[n];
    Array.Fill(aMin, float.MaxValue);

    Zone1Anode.ReadShankVertex(c.Anode, c.Lock, c.LayerMm, fTop - (6.5f * c.LayerMm), 5.5f, aMax, aMin);   // inside layer 6
    Zone1Anode.ReadShankVertex(c.Anode, c.Lock, c.LayerMm, fTop - (10f * c.LayerMm), 5.4f, aMax, aMin);    // on the 9 | 10 boundary
    Zone1Anode.ReadShankVertex(c.Anode, c.Lock, c.LayerMm, c.Anode.LengthMm - 0.01f, 9f, aMax, aMin);      // the lattice's
    Zone1Anode.ReadShankVertex(c.Anode, c.Lock, c.LayerMm, c.Anode.LengthMm, 1f, aMax, aMin);              // the seam face

    Assert.Equal([6, 9, 10, n - 1], Enumerable.Range(0, n).Where(j => aMax[j] > 0f));
    Assert.Equal(5.4f, aMax[9]);
    Assert.Equal(5.4f, aMin[10]);
    Assert.Equal(1f, aMin[n - 1]);
}

// The seam, in two readings: the largest surface must reach from the tip to the top face, and no OTHER surface may
// rise above the seam plane by more than half a voxel. A loose crumb that stays below the plane — the clipped
// lattice carries them right up to its top face, measured on a lattice built without any shank — is counted, never a
// finding. Synthetic strips of triangles (vertex i at Z[i], triangle i·i+1·i+2).
// MUTATION: the above-the-plane rule dropped ⇒ red · the rule widened back to «within 2 voxels under the plane» ⇒ red.
[Fact]
public void The_Seam_Check_Wants_One_Surface_To_The_Top_Face_And_Leaves_The_Lattices_Crumbs_Alone()
{
    MeshCheck c = MeshCheck.Shipped();
    float fL = c.Anode.LengthMm, fTop = fL + c.Lock.ShankLengthMm;
    static (float[] Z, int[] T) Strip(params float[] aZ)
        => (aZ, [.. Enumerable.Range(0, aZ.Length - 2).SelectMany(i => new[] { i, i + 1, i + 2 })]);
    static (float[] Z, int[] T) Join((float[] Z, int[] T) a, (float[] Z, int[] T) b)
        => ([.. a.Z, .. b.Z], [.. a.T, .. b.T.Select(i => i + a.Z.Length)]);
    IReadOnlyList<string> Findings((float[] Z, int[] T) m) => Zone1Anode.IntegratedSeamFindings(c.Anode, c.Lock, c.LayerMm, m.Z, m.T).Findings;

    (float[] Z, int[] T) body = Strip(0f, fL / 2f, fL, fL + 1f, fTop);
    Assert.Empty(Findings(body));
    Assert.Empty(Findings(Join(body, Strip(0f, 0.05f, 0.1f))));                    // a crumb at the tip
    Assert.Empty(Findings(Join(body, Strip(fL - 0.09f, fL - 0.06f, fL - 0.03f))));  // a crumb just under the seam
    Assert.Empty(Findings(Join(body, Strip(fL - 0.05f, fL - 0.02f, fL))));          // … and one that touches the plane

    AssertFinds(Findings(Join(Strip(0f, fL / 3f, fL / 2f, fL), Strip(fL, fL + 1f, fTop))), "NOT one connected surface");
    AssertFinds(Findings(Join(body, Strip(fL + 2f, fL + 2.1f, fL + 2.2f))), "rise above the seam plane");      // an inner shell
    AssertFinds(Findings(Join(body, Strip(fL - 0.05f, fL, fL + 0.05f))), "rise above the seam plane");         // a bubble across the plane
    AssertFinds(Findings(Join(body, Strip(fL + 0.03f, fL + 0.06f, fL + 0.09f))), "rise above the seam plane"); // a piece just above it
}
}
