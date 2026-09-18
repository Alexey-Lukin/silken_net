// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Annular ratchet barbs + a retaining-ring groove on a solid Ti shank — the 01_01 §4.3 mechanical
// lock against PEEK cold-flow creep (BLOCKER-3, HW.26). The part is axisymmetric, so the whole shank
// is one signed-distance field over the outer radius R(z): a base cylinder, asymmetric ratchet teeth
// in the PEEK-contact zone, and a subtractive groove for the DIN-471 ring. Asymmetric = a RATCHET — a
// shallow leading ramp (α, easy hot press-fit insert) and a steep trailing ramp (β, hard pull-out).
//
// The 4th from-scratch IImplicit in the house pattern (cf. the gyroid SDFs in Zone1Anode), chosen over
// ShapeKernel BaseRevolve+LineModulation whose fixed nLengthSteps aliases the steep β edge: an analytic
// SDF resolves at voxel scale and lets the barb-count / asymmetry / groove gates run as pure-logic
// xUnit (no Library.Go), exactly like the gyroid tests.
internal sealed class MechanicalLockShank : IImplicit
{
    private readonly float _fRShank, _fZ0, _fContactLen, _fPitch, _fH, _fLeadLen, _fTrailLen;
    private readonly float _fGrooveZ0, _fGrooveZ1, _fGrooveDepth;

    public MechanicalLockShank(MechanicalLockCem cem)
    {
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
    internal float ProfileRadius(float fZ)
    {
        float fR = _fRShank;
        if (fZ >= _fZ0 && fZ <= _fZ0 + _fContactLen)
        {
            float fLocal = (fZ - _fZ0) - (MathF.Floor((fZ - _fZ0) / _fPitch) * _fPitch);  // t∈[0,pitch)
            fR += Ratchet(fLocal);
        }
        if (fZ >= _fGrooveZ0 && fZ <= _fGrooveZ1) fR -= _fGrooveDepth;
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
// (thin SDF) − a retaining-groove ring BoolSubtract-ed. Self-supports printed gentle-ramp-down as a SEPARATE part
// (01_01 §4.3 A); integrated into the anode, the anode's tip-down (01_02 §1.6) puts the steep face down — open,
// 00_07 HW.26 G4 (external supports allowed — barbs are on the outer shank).
internal static class MechanicalLock
{
    // A lock end carries a DIN-471 groove only when both of its dimensions are positive. ⚖️ 2026-09-18 (00_07 HW.26)
    // removed the ring as a backup on BOTH ends and the Zone-3 groove from the geometry, so the Zone-3 manifests
    // declare 0 × 0 at offset 0 — explicit zeros, never absent keys: an absent key would fill from the record
    // default (gotcha #0a) and silently cut the Zone-1 groove into the flange.
    public static bool HasGroove(MechanicalLockCem cem) => cem.GrooveWidthMm > 0f && cem.GrooveDepthMm > 0f;

    public static Voxels Build(MechanicalLockCem cem)
    {
        float fRShank = cem.ShankDiameterMm / 2f;

        // 1. Solid shank — a true filled cylinder (NOT an SDF render; see BarbRidges).
        Voxels voxShank = new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, fRShank).voxConstruct();

        // 2. Barb ridges — a thin annular shell, fused onto the shank.
        voxShank.BoolAdd(new Voxels(new BarbRidges(cem), voxShank.oCalculateBoundingBox()));

        // 3. Retaining groove (§4.3 B) — subtract an annular ring (depth grooveDepth) over the groove width;
        //    skipped on an end that carries none (a zero-length cylinder is not a groove, it is a degenerate solid).
        if (HasGroove(cem))
        {
            LocalFrame oGroove = new(new Vector3(0f, 0f, cem.GrooveOffsetMm));
            Voxels voxRing = new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank + cem.BarbHeightMm).voxConstruct();
            voxRing.BoolSubtract(new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank - cem.GrooveDepthMm).voxConstruct());
            voxShank.BoolSubtract(voxRing);
        }

        // 4. Central bore (01_01 §1.4): bore==0 ⇒ SOLID shank (monolithic anode — the bus is the metal core);
        //    bore>0 ⇒ the cathode (Zone-3) channel the bus rod threads to the pogo pad.
        if (cem.BoreDiameterMm > 0f)
            voxShank.BoolSubtract(new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, cem.BoreDiameterMm / 2f).voxConstruct());

        return voxShank;
    }

    // The insertion depths this lock admits (00_07 HW.26): where the sleeve MOUTH may sit along the shank,
    // measured in the LOCK's frame — from local z = 0, the free end that enters the PEEK first (gotcha #15).
    // A depth is frame-invariant (entering end → mouth), so AnchorAxialStackCem.Zone1InsertionMm compares directly;
    // what must never be reused in the anode frame is the lock's GEOMETRY (G4), not this scalar.
    //   Min = end of the declared PEEK-contact zone: shallower, the last barbs and the PEEK that has to sit
    //         behind their steep faces are outside the sleeve (01_01 §4.3 A).
    //   Max = near flank of the DIN-471 groove, on an end that still carries one (Zone 1): deeper, the groove is
    //         inside the PEEK. ⚖️ 2026-09-18 (00_07 HW.26) no ring is fitted as a backup on either end and the
    //         Zone-3 groove is gone, so on an end WITHOUT a groove there is no groove flank: its deepest insertion
    //         is the whole shank (the shoulder stops it).
    // ⛔ Declared ceiling: nominal dims only — no depth tolerance of a force-controlled press, no chamfer at
    //    the mouth, and nothing about whether Zone 1 needs a stop against moving DEEPER (HW.26 G1/G3).
    internal readonly record struct InsertionWindow(float MinMm, float MaxMm);

    public static InsertionWindow InsertionWindowMm(MechanicalLockCem cem)
        => new(cem.ContactStartMm + cem.ContactLengthMm, HasGroove(cem) ? cem.GrooveOffsetMm : cem.ShankLengthMm);
}
