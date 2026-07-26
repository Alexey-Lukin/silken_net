// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Cartesian gyroid SDF (bicontinuous, isotropic period) — uniform everywhere (no axis
// singularity, unlike LatticeLibrary's radial ImplicitRadialGyroid near r=0). Still
// bicontinuous, the orientation-agnostic property the founder's decision (б) accepted
// (HW.33). Formula matches the LEAP presets exactly: |eq| − 0.5*wallParam (dimensionless;
// solid where < 0). Per the LEAP guide, a clean wall needs wallParam ≪ the eq amplitude.
// v1 (constant period); the radially GRADED sibling is GradedCartesianGyroid below.
internal sealed class CartesianGyroid(float fPeriodMm, float fWallParam) : IImplicit
{
    private readonly float _fFreq = 2f * MathF.PI / fPeriodMm;

    public float fSignedDistance(in Vector3 vecPt)
    {
        float fX = _fFreq * vecPt.X, fY = _fFreq * vecPt.Y, fZ = _fFreq * vecPt.Z;
        double dEq = (Math.Sin(fX) * Math.Cos(fY)) + (Math.Sin(fY) * Math.Cos(fZ)) + (Math.Sin(fZ) * Math.Cos(fX));
        return (float)(Math.Abs(dEq) - (0.5f * fWallParam));
    }
}

// Radially GRADED cartesian gyroid (anchor v2, 01_01 §5.5). Tapers TWO independent axes from
// the core (r=rCore, the rod axis) to the rim (r=rRim, the outer wall): period (cell/pore size)
// and wallParam (porosity/E). Per the FGS method s=p/(1−ρ), at constant porosity a linear pore
// gradient IS a linear cell-size (period) gradient; wallParam(r) can instead GRADE the porosity
// (founder 2026-06-21 — constant-vs-graded is an open, FEA-gated choice). Phase uses the LEAP-style
// coord/period(r): a spatially-varying frequency is not strictly periodic (cells distort slightly
// across the gradient) but stays bicontinuous → porosity is MEASURED per radial shell, never derived
// (gotcha #4). Topology: sheet = a wall around the minimal surface (|eq|; stretch-dominated, more
// surface); network = one solid channel (one side of eq; bending-dominated, lower E) — the HW.33 axis.
internal sealed class GradedCartesianGyroid : IImplicit
{
    private readonly float _fRCore, _fRRim, _fPeriodCore, _fPeriodRim, _fWallCore, _fWallRim;
    private readonly bool _bNetwork;

    public GradedCartesianGyroid(
        float fRCoreMm, float fRRimMm,
        float fPeriodCoreMm, float fPeriodRimMm,
        float fWallCore, float fWallRim,
        bool bNetwork)
    {
        _fRCore = fRCoreMm;
        _fRRim = fRRimMm;
        _fPeriodCore = fPeriodCoreMm;
        _fPeriodRim = fPeriodRimMm;
        _fWallCore = fWallCore;
        _fWallRim = fWallRim;
        _bNetwork = bNetwork;
    }

    public float fSignedDistance(in Vector3 vecPt)
    {
        // Radial blend 0 (core/axis) → 1 (rim), from the cylindrical radius about the rod's Z axis.
        float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
        float fT = _fRRim > _fRCore ? Math.Clamp((fR - _fRCore) / (_fRRim - _fRCore), 0f, 1f) : 0f;
        float fPeriod = _fPeriodCore + ((_fPeriodRim - _fPeriodCore) * fT);
        float fWall = _fWallCore + ((_fWallRim - _fWallCore) * fT);
        float fFreq = 2f * MathF.PI / fPeriod;

        float fX = fFreq * vecPt.X, fY = fFreq * vecPt.Y, fZ = fFreq * vecPt.Z;
        double dEq = (Math.Sin(fX) * Math.Cos(fY)) + (Math.Sin(fY) * Math.Cos(fZ)) + (Math.Sin(fZ) * Math.Cos(fX));

        // sheet: solid in the band around the minimal surface. network: solid on one side of it,
        // level-shifted by wallParam so a larger param ⇒ more metal ⇒ lower porosity (same sense as
        // sheet). Both are MEASURE-calibrated — the same wallParam yields different porosity per topology.
        return _bNetwork
            ? (float)(dEq - (0.5f * (fWall - 1f)))
            : (float)(Math.Abs(dEq) - (0.5f * fWall));
    }
}

// Stepped (heterostructure) gyroid — concentric zones, each at a CONSTANT period (so zero
// phase-distortion inside a zone, unlike the continuous GradedCartesianGyroid). Gives a STRONG
// pore-size contrast at constant porosity: each zone is self-similar → ~same porosity, different
// cell size. The only distortion is a thin phase-mismatch ring at the zone boundary (negligible
// volume), vs the continuous gradient smearing distortion through the whole part. This is the
// SOTA "heterostructure gradient" pattern (vs density / cell-size gradients).
internal sealed class ZonedGyroid(float fRMidMm, float fPeriodCoreMm, float fPeriodRimMm, float fWallParam) : IImplicit
{
    public float fSignedDistance(in Vector3 vecPt)
    {
        float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
        float fFreq = 2f * MathF.PI / (fR < fRMidMm ? fPeriodCoreMm : fPeriodRimMm);
        float fX = fFreq * vecPt.X, fY = fFreq * vecPt.Y, fZ = fFreq * vecPt.Z;
        double dEq = (Math.Sin(fX) * Math.Cos(fY)) + (Math.Sin(fY) * Math.Cos(fZ)) + (Math.Sin(fZ) * Math.Cos(fX));
        return (float)(Math.Abs(dEq) - (0.5f * fWallParam));
    }
}

// Zone-1 gyroid anode (01_01 §5): a gyroid Ti rod (Ø per CEM, founder Ø11) with a central SOLID
// bus-rod core (01_01 §1.4 monolithic — BuildMonolithic) inside the gyroid annulus, clipped from a
// BasePipe envelope. Bicontinuous, orientation-
// agnostic (founder decision (б), HW.33). v2 = radially graded (period + porosity + topology),
// CEM-driven; a constant CEM (no Rim fields, sheet) renders the v1 uniform gyroid. Barbs
// (01_01 §4.3A) are a separate session (00_07).
internal static class Zone1Anode
{
    // The gyroid-annulus inner radius: the monolithic bus-rod surface (01_01 §1.4) when a rod is set,
    // else the legacy hollow bore. Shared by the envelope (porosity ref + clip) and the gyroid gradient core
    // so the lattice annulus and the solid rod meet exactly.
    internal static float InnerRadiusMm(AnchorCem cem)
        => cem.BusRodDiameterMm > 0f ? cem.BusRodDiameterMm / 2f : cem.BoreDiameterMm / 2f;

    // Solid pipe envelope (outer Ø + inner Ø) — also the porosity reference volume (the gyroid annulus only;
    // the solid bus rod is added in BuildMonolithic and is NOT part of the porosity measurement).
    public static Voxels Envelope(AnchorCem cem)
    {
        BasePipe oPipe = new(new LocalFrame(), cem.LengthMm, InnerRadiusMm(cem), cem.OuterDiameterMm / 2f);
        return oPipe.voxConstruct();
    }

    // Constant (v1) when there is no Rim taper and sheet topology; graded otherwise.
    // A Rim field of 0 means "equals core" (back-compat with v1 manifests).
    public static IImplicit Gyroid(AnchorCem cem)
    {
        float fPeriodRim = cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;
        float fWallRim = cem.GyroidWallParamRim > 0f ? cem.GyroidWallParamRim : cem.GyroidWallParam;
        bool bNetwork = cem.Topology.Equals("network", StringComparison.OrdinalIgnoreCase);

        if (cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase))
            return new ZonedGyroid(
                (InnerRadiusMm(cem) + (cem.OuterDiameterMm / 2f)) / 2f,
                cem.GyroidPeriodMm, fPeriodRim, cem.GyroidWallParam);

        bool bGraded = fPeriodRim != cem.GyroidPeriodMm || fWallRim != cem.GyroidWallParam || bNetwork;

        return bGraded
            ? new GradedCartesianGyroid(
                InnerRadiusMm(cem), cem.OuterDiameterMm / 2f,
                cem.GyroidPeriodMm, fPeriodRim,
                cem.GyroidWallParam, fWallRim, bNetwork)
            : new CartesianGyroid(cem.GyroidPeriodMm, cem.GyroidWallParam);
    }

    // Render the gyroid into the envelope's bbox via the Voxels(IImplicit, BBox3) ctor,
    // then BoolIntersect to clip to the pipe. The envelope is left intact (BoolIntersect
    // mutates the gyroid grid) so it can serve as the porosity reference volume.
    public static Voxels Anode(AnchorCem cem, Voxels voxEnvelope)
    {
        Voxels voxGyroid = new(Gyroid(cem), voxEnvelope.oCalculateBoundingBox());
        voxGyroid.BoolIntersect(voxEnvelope);
        return voxGyroid;
    }

    // The full standalone part = the gyroid annulus (porosity-measured separately, via Anode) PLUS the
    // solid monolithic bus-rod core (01_01 §1.4). The rod is a SOLID body → ShapeKernel voxConstruct +
    // BoolAdd (gotcha #9 — never the narrow-band SDF ctor; the same split as MechanicalLock's solid shank).
    // A rod-less CEM (BusRodDiameterMm==0) returns the bare gyroid → back-compat with the v1 manifests.
    // The solid monolithic bus-rod core as voxels (01_01 §1.4) — ShapeKernel voxConstruct (gotcha #9,
    // never the narrow-band SDF ctor for a solid). Shared by BuildMonolithic (the part) + the verify
    // rod-presence MEASURE (gotcha #4 — don't assume the BoolAdd landed; measure it).
    public static Voxels BusRod(AnchorCem cem)
        => new BaseCylinder(new LocalFrame(), cem.LengthMm, cem.BusRodDiameterMm / 2f).voxConstruct();

    public static Voxels BuildMonolithic(AnchorCem cem)
    {
        Voxels voxAnode = Anode(cem, Envelope(cem));
        if (cem.BusRodDiameterMm > 0f)
            voxAnode.BoolAdd(BusRod(cem));
        return voxAnode;
    }

    public static Voxels Build(AnchorCem cem) => BuildMonolithic(cem);
}
