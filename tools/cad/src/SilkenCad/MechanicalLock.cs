// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Annular ratchet barbs on a solid Ti shank — the 01_01 §4.3 mechanical lock against PEEK cold-flow creep
// (BLOCKER-3, HW.26) — plus a DIN-471 groove on an end that still carries one: the ring as a backup was removed
// on BOTH ends ⚖️ 2026-09-18 (00_07 HW.26), the Zone-3 groove with it, and the Zone-1 groove stays until G3.
// The part is axisymmetric, so the whole shank is one signed-distance field over the outer radius R(z): a base
// cylinder, asymmetric ratchet teeth in the PEEK-contact zone, and a subtractive groove where HasGroove. Asymmetric
// = a RATCHET — a shallow leading ramp (α, easy hot press-fit insert) and a steep trailing ramp (β, hard pull-out).
//
// The 4th from-scratch IImplicit in the house pattern (cf. the gyroid SDFs in Zone1Anode), chosen over
// ShapeKernel BaseRevolve+LineModulation whose fixed nLengthSteps aliases the steep β edge: an analytic
// SDF resolves at voxel scale and lets the barb-count / asymmetry / groove gates run as pure-logic
// xUnit (no Library.Go), exactly like the gyroid tests.
internal sealed class MechanicalLockShank : IImplicit
{
    private readonly float _fRShank, _fZ0, _fContactLen, _fPitch, _fH, _fLeadLen, _fTrailLen;
    private readonly float _fGrooveZ0, _fGrooveZ1, _fGrooveDepth;
    private readonly bool _bGroove;

    public MechanicalLockShank(MechanicalLockCem cem)
    {
        _bGroove = MechanicalLock.HasGroove(cem);
        _fRShank = cem.ShankDiameterMm / 2f;
        _fZ0 = cem.ContactStartMm;
        _fContactLen = cem.ContactLengthMm;
        _fPitch = cem.ContactLengthMm / cem.BarbRows;
        _fH = cem.BarbHeightMm;
        _fLeadLen = cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f);    // shallow α ⇒ long
        _fTrailLen = cem.BarbHeightMm / MathF.Tan(cem.TrailAngleDeg * MathF.PI / 180f);  // steep β ⇒ short
        _fGrooveZ0 = cem.GrooveOffsetMm;
        _fGrooveZ1 = cem.GrooveOffsetMm + cem.GrooveWidthMm;
        _fGrooveDepth = cem.GrooveDepthMm;
    }

    // Tooth height at local position t∈[0,pitch): rise 0→h over the leading ramp, fall h→0 over the
    // trailing ramp, flat 0 in the gap. t grows AWAY from local z = 0 — the end that enters the PEEK first —
    // so the shallow α ramp always meets the PEEK first and the steep β face resists pull-out (no direction
    // knob: see Cem.cs). base = leadLen + trailLen = h·(cot α + cot β) must be < pitch so the teeth stay
    // separated (a clean cylinder between rows).
    private float Ratchet(float fT)
    {
        if (fT < _fLeadLen) return _fH * (fT / _fLeadLen);
        float fAfter = fT - _fLeadLen;
        if (fAfter < _fTrailLen) return _fH * (1f - (fAfter / _fTrailLen));
        return 0f;
    }

    // Outer radius profile R(z): base shank + barb ridge (contact zone) − groove notch. Exposed for the
    // golden-metrics sampler (Validation.MeasureLock) so barb count/height/base/groove are MEASURED.
    // ⛔ The notch is gated by HasGroove, exactly like the Build that cuts it: the band is CLOSED, so a zero-width
    //    groove with a positive depth still notched z = offset here while Build cut nothing — the profile, and every
    //    metric sampled off it, would have described a groove the part does not have.
    internal float ProfileRadius(float fZ)
    {
        float fR = _fRShank;
        if (fZ >= _fZ0 && fZ <= _fZ0 + _fContactLen)
        {
            float fLocal = (fZ - _fZ0) - (MathF.Floor((fZ - _fZ0) / _fPitch) * _fPitch);  // t∈[0,pitch)
            fR += Ratchet(fLocal);
        }
        if (_bGroove && fZ >= _fGrooveZ0 && fZ <= _fGrooveZ1) fR -= _fGrooveDepth;
        return fR;
    }

    // Radial SDF only (solid where r < R(z)); the cylinder envelope's BoolIntersect supplies the z
    // end-caps + outer clamp — the gotcha #1 ctor-render route, mirroring Zone1Anode.Anode.
    public float fSignedDistance(in Vector3 vecPt)
    {
        float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
        return fR - ProfileRadius(vecPt.Z);
    }
}

// A thin annular ridge shell (rShank ≤ r ≤ rShank+ratchet) over the contact zone, BoolAdd-ed onto a SOLID
// cylinder. A FILLED body is not rendered straight from an SDF here: a field left OPEN at the bbox caps renders
// as a HOLLOW tube (picogk gotcha #9 — the old «the narrow band excludes the solid core» mechanism was
// falsified 2026-09-12; a CLOSED field renders solid, and the gyroid is closed by its envelope intersect).
// Solid bodies come from ShapeKernel voxConstruct; only thin features go through the SDF — the Ti-coin split.
internal sealed class BarbRidges(MechanicalLockCem cem) : IImplicit
{
    private readonly MechanicalLockShank _shank = new(cem);
    private readonly float _fRShank = cem.ShankDiameterMm / 2f;

    public float fSignedDistance(in Vector3 vecPt)
    {
        float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
        float fROuter = _shank.ProfileRadius(vecPt.Z);
        if (fROuter <= _fRShank + 1e-4f) return 1f;            // no ridge at this z (gap or groove)
        return MathF.Max(_fRShank - fR, fR - fROuter);         // solid in the ridge shell [rShank, rShank+ratchet]
    }
}

// Builds the §4.3 shank. Zone 1 (real Ø11) is a self-contained demo part, not integrated into the gyroid rod
// (separate session, 00_07); Zone 3 (placeholder Ø) is also the cathode flange's shank — `CathodeFlange.Build`
// calls this. A SOLID cylinder (ShapeKernel) + barb ridges BoolAdd-ed
// (thin SDF) − a retaining-groove ring BoolSubtract-ed where HasGroove. Self-supports printed gentle-ramp-down as a SEPARATE part
// (01_01 §4.3 A); integrated into the anode, the anode's tip-down (01_02 §1.6) puts the steep face down — open,
// 00_07 HW.26 G4 (external supports allowed — barbs are on the outer shank).
internal static class MechanicalLock
{
    // A lock end carries a DIN-471 groove only when both of its dimensions are positive. ⚖️ 2026-09-18 (00_07 HW.26)
    // removed the ring as a backup on BOTH ends and the Zone-3 groove from the geometry, so the Zone-3 manifests
    // declare 0 × 0 at offset 0 — explicit zeros, never absent keys: an absent key fills from the record default
    // (gotcha #0a), and MechanicalLockCem's defaults ARE the Zone-1 groove. (CathodeFlangeCem's are zero since the
    // same day, because the assembly and stack manifests build their flange from defaults alone.)
    public static bool HasGroove(MechanicalLockCem cem) => cem.GrooveWidthMm > 0f && cem.GrooveDepthMm > 0f;

    public static Voxels Build(MechanicalLockCem cem)
    {
        float fRShank = cem.ShankDiameterMm / 2f;

        // 1. Solid shank — a true filled cylinder (NOT an SDF render; see BarbRidges).
        Voxels voxShank = new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, fRShank).voxConstruct();

        // 2. Barb ridges — a thin annular shell, fused onto the shank, rendered in RidgeBox (below): the ridges stand
        //    proud of the cylinder, so the cylinder's own box is too small for them.
        voxShank.BoolAdd(new Voxels(new BarbRidges(cem), RidgeBox(cem, voxShank.oCalculateBoundingBox(), voxShank.fVoxelSize)));

        // 3. Retaining groove (§4.3 B) — subtract an annular ring (depth grooveDepth) over the groove width;
        //    skipped on an end that carries none (a zero-length cylinder is not a groove, it is a degenerate solid).
        if (HasGroove(cem))
        {
            LocalFrame oGroove = new(new Vector3(0f, 0f, cem.GrooveOffsetMm));
            Voxels voxRing = new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank + cem.BarbHeightMm).voxConstruct();
            voxRing.BoolSubtract(new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank - cem.GrooveDepthMm).voxConstruct());
            voxShank.BoolSubtract(voxRing);
        }

        // 4. Central bore (01_01 §1.4): bore==0 ⇒ SOLID shank (the Zone-1 end — the anode carries no core, the bus
        //    is a wire welded to its TOP face, ⚖️ 2026-09-18); bore>0 ⇒ the cathode (Zone-3) channel the bus wire
        //    threads to the pogo pad.
        if (cem.BoreDiameterMm > 0f)
            voxShank.BoolSubtract(new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, cem.BoreDiameterMm / 2f).voxConstruct());

        return voxShank;
    }

    // The insertion depths this lock admits (00_07 HW.26): where the sleeve MOUTH may sit along the shank,
    // measured in the LOCK's frame — from local z = 0, the free end that enters the PEEK first (gotcha #15).
    // A depth is frame-invariant (entering end → mouth), so AxialStack.Zone1InsertionMm (= the whole shank since G1) compares directly;
    // what must never be reused in the anode frame is the lock's GEOMETRY (G4), not this scalar.
    //   Min = end of the declared PEEK-contact zone: shallower, the last barbs and the PEEK that has to sit
    //         behind their steep faces are outside the sleeve (01_01 §4.3 A).
    //   Max = the whole shank, on EVERY end. ⚖️ 2026-09-18 (00_07 HW.26, «Ціна»): the window LOST its upper bound.
    //         It used to be the near flank of the DIN-471 groove — deeper, the ring could not be fitted
    //         once pressed — but no ring is fitted as a backup on either end any more, so a groove bounds nothing,
    //         including the Zone-1 groove that stays in the geometry until G3. What is left is the extent of the
    //         lock itself: on Zone 3 the shoulder stops the press there; on Zone 1 the PRESS FIXTURE does, not the
    //         part (⚖️ G1 2026-10-12, 01_01 §4.3 A) — so the shipped insertion IS this Max, and `verify` prints both.
    // ⛔ Declared ceiling: nominal dims only — no depth tolerance of a force-controlled press, no chamfer at
    //    the mouth. The Zone-1 `shank_length_mm` is the physical shank since G1 (branch (А)), so its Max is the anode's.
    // ⚠️ Mirrored BY VALUE in `tools/in_silico/scripts/55_bus_mechanical.py` (`lock_insertion_window_mm`): no gate
    //    spans the pair, so a verdict that moves this window or the prose above edits both.
    internal readonly record struct InsertionWindow(float MinMm, float MaxMm);

    public static InsertionWindow InsertionWindowMm(MechanicalLockCem cem)
        => new(cem.ContactStartMm + cem.ContactLengthMm, cem.ShankLengthMm);

    // The box the barb ridges are rendered in: the bare shank's, grown radially by the barb height plus the 3-voxel
    // band the runtime keeps around a surface. Pure, so xUnit holds it without the voxel runtime.
    // 🔴 Until 2026-11-15 the ridges were rendered in the bare cylinder's own box, whose four side planes are tangent
    //    to it: every tooth came out cut down where it crosses the X and Y axes (crest 0.11 mm low on the axis, whole
    //    again ≈ 10° either side — measured at voxel 0.05), on the lock's own STL and on the flange's shank alike —
    //    and nothing saw it, because `verify` measured the tooth on the analytic profile. `verify` now reads the crest
    //    off the built mesh by azimuth (CrestFindings below); no gate runs `verify`, so the pin on THIS function is
    //    what an automatic run would red on if the bare box came back.
    internal static BBox3 RidgeBox(MechanicalLockCem cem, BBox3 oShank, float fVoxelMm)
    {
        float fProud = cem.BarbHeightMm + (3f * fVoxelMm);
        return new BBox3(oShank.vecMin - new Vector3(fProud, fProud, 0f), oShank.vecMax + new Vector3(fProud, fProud, 0f));
    }

    // ── The barb CRESTS of a built mesh, read BY AZIMUTH — pure, so xUnit pins the comparison; reading the mesh is
    //    the verb's (`verify mechanical_lock` · `verify cathode_flange`; a body that carries the lock in another frame
    //    hands its vertices in lock-local coordinates). A crest read as one number per tooth — the largest radius
    //    anywhere round it — is exactly what hid the clipped ridges: the tooth was whole on most of the circle. ──

    // Sectors of 3°, centred on k·3°, so each of the four axis directions sits in the MIDDLE of one. A sector reads the
    // LARGEST radius in it, so a crest low over an arc of 6° or more is seen wherever the arc lies (any such arc holds
    // a whole sector), and a narrower one can hide between two sectors that each keep a sound vertex. The cut this
    // check was built for was below the floor over ≈ 15° at each axis.
    internal const int CrestSectors = 120;
    // A vertex counts for a row's crest within 2 voxels of its analytic z (a meshed face lands within a voxel of its
    // nominal, and the layer that straddles it reads either side); a sector's crest may read 1 voxel off the
    // manifest's, either way — the sharp edge meshes rounded, short of its nominal by a fraction of a voxel.
    // ⛔ Declared ceilings of that one-voxel floor, measured on the Zone-1 lock's own build (2026-11-15):
    //    • a sound crest keeps 0.011–0.033 mm above it over voxels 0.03–0.08 — 0.019 at the shipped 0.05, the least at
    //      0.032 — so a kernel or voxel change that rounds the edge a little more reds a sound mesh;
    //    • the floor moves with the voxel, so does what passes: a crest low by up to one voxel is let through, and from
    //      voxel 0.065 up the bare-box cut itself passed (0.065 · 0.07 · 0.08 — exit 0 on the old box);
    //    • it is not derived from the tooth: a sharper apex meshes shorter, so a future manifest with a steeper tooth
    //      may red a sound mesh.
    internal const int CrestAxialWindowVoxels = 2;
    internal const float CrestRadialToleranceVoxels = 1f;

    // The analytic crest of barb row nRow (0-based from local z = 0), lock-local z.
    internal static float CrestZMm(MechanicalLockCem cem, int nRow)
        => cem.ContactStartMm + (nRow * cem.ContactLengthMm / cem.BarbRows)
           + (cem.BarbHeightMm / MathF.Tan(cem.LeadAngleDeg * MathF.PI / 180f));

    // Feeds one mesh vertex, in LOCK-LOCAL coordinates, into aCrest[row, sector] — the largest radius seen there.
    internal static void ReadCrestVertex(MechanicalLockCem cem, float fVoxelMm, Vector3 vecLockLocal, float[,] aCrest)
    {
        int nRow = (int)MathF.Round((vecLockLocal.Z - CrestZMm(cem, 0)) * cem.BarbRows / cem.ContactLengthMm);
        if (nRow < 0 || nRow >= cem.BarbRows
            || MathF.Abs(vecLockLocal.Z - CrestZMm(cem, nRow)) > CrestAxialWindowVoxels * fVoxelMm) return;
        int nSector = (int)MathF.Round(MathF.Atan2(vecLockLocal.Y, vecLockLocal.X) * CrestSectors / (2f * MathF.PI));
        nSector = ((nSector % CrestSectors) + CrestSectors) % CrestSectors;
        aCrest[nRow, nSector] = MathF.Max(
            aCrest[nRow, nSector], MathF.Sqrt((vecLockLocal.X * vecLockLocal.X) + (vecLockLocal.Y * vecLockLocal.Y)));
    }

    // Every sector of every row must carry its crest, no lower than the floor and no higher than the same room above
    // the manifest's: one finding per row and side, naming the extreme reading, where it is and over how much of the
    // circle the tooth is off. (A sector no vertex fed reads 0.)
    internal static (string Summary, IReadOnlyList<string> Findings) CrestFindings(MechanicalLockCem cem, float fVoxelMm, float[,] aCrest)
    {
        float fNominal = (cem.ShankDiameterMm / 2f) + cem.BarbHeightMm;
        float fFloor = fNominal - (CrestRadialToleranceVoxels * fVoxelMm), fCeiling = fNominal + (CrestRadialToleranceVoxels * fVoxelMm);
        var aFindings = new List<string>();
        float fLowest = float.MaxValue, fHighest = float.MinValue;
        for (int nRow = 0; nRow < aCrest.GetLength(0); nRow++)
        {
            int nLow = 0, nHigh = 0, nLowAt = 0, nHighAt = 0;
            for (int s = 0; s < CrestSectors; s++)
            {
                if (aCrest[nRow, s] < fFloor) nLow++;
                if (aCrest[nRow, s] > fCeiling) nHigh++;
                if (aCrest[nRow, s] < aCrest[nRow, nLowAt]) nLowAt = s;
                if (aCrest[nRow, s] > aCrest[nRow, nHighAt]) nHighAt = s;
            }
            fLowest = MathF.Min(fLowest, aCrest[nRow, nLowAt]);
            fHighest = MathF.Max(fHighest, aCrest[nRow, nHighAt]);
            if (nLow > 0)
                aFindings.Add($"barb row {nRow + 1}: the crest is LOW over {nLow} of {CrestSectors} sectors of the circle — lowest r " +
                              $"{aCrest[nRow, nLowAt]:F3} at azimuth {nLowAt * 360f / CrestSectors:F0}°, where the manifest gives {fNominal:F3} " +
                              $"and the check allows {fFloor:F3}");
            if (nHigh > 0)
                aFindings.Add($"barb row {nRow + 1}: the crest stands PROUD over {nHigh} of {CrestSectors} sectors of the circle — highest r " +
                              $"{aCrest[nRow, nHighAt]:F3} at azimuth {nHighAt * 360f / CrestSectors:F0}°, where the manifest gives {fNominal:F3} " +
                              $"and the check allows {fCeiling:F3}");
        }
        return ($"barb crests by azimuth ({aCrest.GetLength(0)} rows × {CrestSectors} sectors): r {fLowest:F3}…{fHighest:F3}, " +
                $"manifest {fNominal:F3}, allowed {fFloor:F3}…{fCeiling:F3}", aFindings);
    }
}
