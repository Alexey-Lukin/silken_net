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
    private readonly int _iDir;
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
        _iDir = cem.BarbDirection < 0 ? -1 : 1;
        _fGrooveZ0 = cem.GrooveOffsetMm;
        _fGrooveZ1 = cem.GrooveOffsetMm + cem.GrooveWidthMm;
        _fGrooveDepth = cem.GrooveDepthMm;
    }

    // Tooth height at local position t∈[0,pitch): rise 0→h over the leading ramp, fall h→0 over the
    // trailing ramp, flat 0 in the gap. base = leadLen + trailLen = h·(cot α + cot β) must be < pitch
    // so the teeth stay separated (a clean cylinder between rows).
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
            if (_iDir < 0) fLocal = _fPitch - fLocal;                                      // mirror ⇒ opposite lean
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

// A thin annular ridge shell (rShank ≤ r ≤ rShank+ratchet) over the contact zone — narrow-band-safe so
// it can be BoolAdd-ed onto a SOLID cylinder. A FILLED body must NOT be rendered straight from an SDF:
// PicoGK's Voxels(IImplicit,bbox) ctor builds a NARROW-BAND field, so a solid core falls outside the band
// and renders as a HOLLOW SHELL (gotcha — the gyroid escapes it only because it is thin-walled everywhere).
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

// Builds the demo shank (Zone-1 real Ø11, Zone-3 placeholder Ø) — a self-contained §4.3 part, not integrated
// into the gyroid rod (separate session, 00_07). A SOLID cylinder (ShapeKernel) + barb ridges BoolAdd-ed
// (thin SDF) − a retaining-groove ring BoolSubtract-ed. Print per 01_02 §1.6 (vertical, tip-down; external
// supports allowed — barbs are on the outer shank).
internal static class MechanicalLock
{
    public static Voxels Build(MechanicalLockCem cem)
    {
        float fRShank = cem.ShankDiameterMm / 2f;

        // 1. Solid shank — a true filled cylinder (NOT an SDF render; see BarbRidges).
        Voxels voxShank = new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, fRShank).voxConstruct();

        // 2. Barb ridges — a thin annular shell, narrow-band-safe, fused onto the shank.
        voxShank.BoolAdd(new Voxels(new BarbRidges(cem), voxShank.oCalculateBoundingBox()));

        // 3. Retaining groove (§4.3 B) — subtract an annular ring (depth grooveDepth) over the groove width.
        LocalFrame oGroove = new(new Vector3(0f, 0f, cem.GrooveOffsetMm));
        Voxels voxRing = new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank + cem.BarbHeightMm).voxConstruct();
        voxRing.BoolSubtract(new BaseCylinder(oGroove, cem.GrooveWidthMm, fRShank - cem.GrooveDepthMm).voxConstruct());
        voxShank.BoolSubtract(voxRing);

        // 4. Central bore (01_01 §1.4): bore==0 ⇒ SOLID shank (monolithic anode — the bus is the metal core);
        //    bore>0 ⇒ the cathode (Zone-3) channel the bus rod threads to the pogo pad.
        if (cem.BoreDiameterMm > 0f)
            voxShank.BoolSubtract(new BaseCylinder(new LocalFrame(), cem.ShankLengthMm, cem.BoreDiameterMm / 2f).voxConstruct());

        return voxShank;
    }
}
