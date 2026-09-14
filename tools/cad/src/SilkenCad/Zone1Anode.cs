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
// ⚠ That is the SHEET reading of the parameter and it does not generalise: the network branch treats
// the same number as a LEVEL (eq − 0.5(w−1)), where ≪-the-amplitude is not the rule and 0 / negative
// are ordinary values. This class is sheet-only; the branch lives in GradedCartesianGyroid.
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

// First-order NORMALISATION of any implicit field: d ≈ f / |∇f| (00_07 HW.49).
//
// 🔴 Why this exists. `IImplicit.fSignedDistance` is contractually a distance in MILLIMETRES — the
// runtime clamps the stored field at `3 × voxel` mm — while our gyroids return the VALUE of the
// gyroid equation, which is dimensionless and rises `|∇eq| · k` times faster (k = 2π/period). Measured
// 2026-09-12: the active half-band is 0.83 voxels at period 2.5 mm, 0.67 at 2.0, 0.43 on a 1.3 mm rim,
// against OpenVDB's requirement of more than one — and it does NOT scale with the voxel, because clamp
// and field shrink together. Dividing by the gradient magnitude restores millimetres to first order.
//
// ⛔ The zero set is UNCHANGED (f/|∇f| = 0 ⟺ f = 0), so this cannot move the ideal geometry — only what
//    lands in the grid. If a measured porosity DOES move, what moved is what we had been measuring.
// ⚠️ Central differences rather than an analytic gradient on purpose: the graded field's frequency
//    varies with radius, so its true gradient carries a `∇k·coord` term that an analytic derivative of
//    the constant-period formula would omit — the very term gotcha #5 blames for the graded porosity
//    collapse. Differences absorb it for free. Cost: 6 extra field evaluations per sample.
// ⚠️ Declared ceiling: FIRST order. A sheet field carries a crease at eq = 0 where the numeric
//    gradient collapses; `fFloor` keeps the division well-conditioned there instead of exploding.
internal sealed class NormalisedField(IImplicit oInner, float fStepMm, float fFloor = 1e-4f) : IImplicit
{
    public float fSignedDistance(in Vector3 vecPt)
    {
        Vector3 vecAt = vecPt;
        float fValue = oInner.fSignedDistance(vecAt);
        float fGx = Slope(vecAt, new Vector3(fStepMm, 0f, 0f));
        float fGy = Slope(vecAt, new Vector3(0f, fStepMm, 0f));
        float fGz = Slope(vecAt, new Vector3(0f, 0f, fStepMm));
        float fMag = MathF.Sqrt((fGx * fGx) + (fGy * fGy) + (fGz * fGz));
        return fMag > fFloor ? fValue / fMag : fValue;
    }

    private float Slope(Vector3 vecAt, Vector3 vecStep)
    {
        Vector3 vecPlus = vecAt + vecStep, vecMinus = vecAt - vecStep;
        return (oInner.fSignedDistance(vecPlus) - oInner.fSignedDistance(vecMinus)) / (2f * fStepMm);
    }
}

// The two structuring elements of DilatedField below. The name is the mode, the face offset is its ONE length.
internal enum DilationMode { Downskin, Isotropic }

// Minkowski DILATION of a part's lattice by a structuring element of ONE length in mm (00_07 HW.51) — the
// face-offset SENSITIVITY of the voxel-FE, read before discretisation so Connectivity and VoxelFea stay untouched.
//
// 🔴 What it answers, and what it does NOT. It moves the faces of the MODELLED part by a hypothetical offset, so
//    every number measured through it is still the geometric INTENT — never the printed body. The printed excess
//    is a vendor answer per face orientation (down · vertical · up), with state and method, and nobody has given
//    it (the question rides the DMLS letter, vendor_templates.md §Processing п.8). Until then a row is a point on
//    a sensitivity curve, and a caption that calls it "as printed" is false.
//
// The operation. p is solid ⟺ the inner field is solid at p, OR ∃ q in the element: p + q is solid AND p + q
// lies inside the part body (fnInBody). Two rules carry the whole design:
//   • The ORIGIN is never clipped. At offset 0 the element is empty and this returns the inner field's own sign,
//     so the sampled grid is the intent grid bit for bit — including cells a sampler reads just past the body
//     end, which a clipped origin would silently empty. That is what makes the zero row an identity CONTROL.
//   • A SHIFTED sample takes metal only from inside the body. Unclipped, the lattice field continues past the
//     rim, the bore and both ends, and an isotropic element would grow that phantom lattice into the loaded rim.
//
// Modes, and the unit of the offset (a FACE displacement, not a thickness):
//   • Downskin — a segment of length L along +build direction: p is solid if metal lies within L ABOVE it, so
//     metal is added on the −BD side of down-facing faces. A face whose outward normal is exactly −BD moves by
//     L, one inclined θ from it by L·cos θ; vertical and upward faces do not move.
//   • Isotropic — a ball of RADIUS R: every face moves outward by R. ⚠️ R is not "extra wall": a ligament
//     thickens by 2R, so a literal 0.45 mm of radius is a different, far larger experiment.
//
// ⛔ Returns ±1, NOT a distance. The IImplicit contract is millimetres; this reads only the SIGN of the inner
//    field and must never be rendered through a Voxels ctor — it exists for the grid samplers, which read `< 0`.
//
// ⚠️ DECLARED CEILING — the discretisation, in mm and independent of any FE step (ElementSpacingMm = δ):
//   • Downskin: the segment at steps ≤ δ, far end exact. Exact on any face whose solid chord along BD is ≥ δ;
//     a sliver thinner than δ along BD can be crossed without a hit.
//   • Isotropic: the centre plus concentric shells at radial steps ≤ δ, each covered by a Fibonacci set at ~δ
//     spacing, the outer shell exactly at R. On a face thicker than R the offset falls SHORT by R(1 − cos α), α
//     the OUTER shell's covering angle (≈ 2.7/√N rad for N directions) — so that shell never takes fewer than
//     OuterShellMinDirections, and the shortfall is ≤ 0.49 % of R at every radius swept (measured; the pin
//     Dilation_Falls_Short_On_A_Flat_Face_By_A_Declared_Fraction_Only holds 0.6 %). δ alone would leave 79
//     directions at R = 0.05 and a 4.7 % shortfall. A solid feature thinner than ~δ inside the ball can be missed:
//     the intent lattice has none (a network ligament is ≈ 0.36·period ≫ δ); the slivers the body clip cuts at
//     the rim, bore and ends do.
//   • Both are INNER approximations: every sample lies inside the exact element, so no metal is ever added
//     that the exact Minkowski sum would not add.
//   • Cost: the ball holds ~(R/δ)³ samples (≈ 7 200 at R = 0.225 mm), and a pore cell farther than R from metal
//     pays every one of them — iso grids take minutes where downskin takes seconds.
internal sealed class DilatedField(IImplicit oInner, Func<Vector3, bool> fnInBody, Vector3[] aElement) : IImplicit
{
    internal const float ElementSpacingMm = 0.02f;
    internal const int OuterShellMinDirections = 720;

    public float fSignedDistance(in Vector3 vecPt)
    {
        bool bSolid = oInner.fSignedDistance(vecPt) < 0f; // the origin — never clipped (header)
        for (int i = 0; i < aElement.Length && !bSolid; i++)
        {
            Vector3 vecAt = vecPt + aElement[i];
            bSolid = fnInBody(vecAt) && oInner.fSignedDistance(vecAt) < 0f;
        }
        return bSolid ? -1f : 1f;
    }

    // The element's sample offsets for one face offset, origin EXCLUDED (the field always tests it). Double
    // arithmetic, so the far end of the segment and the outer shell land on the declared length exactly.
    internal static Vector3[] Element(DilationMode mode, float fFaceOffsetMm, Vector3 vecBuildDirection)
    {
        if (fFaceOffsetMm < 0f)
            throw new ArgumentOutOfRangeException(nameof(fFaceOffsetMm), fFaceOffsetMm,
                "a negative face offset is an EROSION — a different operation, not a smaller dilation");
        var aOffsets = new List<Vector3>();
        int nSteps = (int)Math.Ceiling(fFaceOffsetMm / (double)ElementSpacingMm);
        if (mode == DilationMode.Downskin)
        {
            for (int i = 1; i <= nSteps; i++)
                aOffsets.Add(vecBuildDirection * (float)((double)fFaceOffsetMm * i / nSteps));
            return [.. aOffsets];
        }

        double dGoldenAngle = Math.PI * (3.0 - Math.Sqrt(5.0));
        for (int m = nSteps; m >= 1; m--) // outer shell first: for a pore cell near metal it holds the largest hit cap
        {
            double dRadius = (double)fFaceOffsetMm * m / nSteps;
            int nDirs = Math.Max(m == nSteps ? OuterShellMinDirections : 1,
                (int)Math.Ceiling(4.0 * Math.PI * dRadius * dRadius / (ElementSpacingMm * (double)ElementSpacingMm)));
            for (int i = 0; i < nDirs; i++)
            {
                double dZ = 1.0 - (((2.0 * i) + 1.0) / nDirs);
                double dRho = Math.Sqrt(1.0 - (dZ * dZ));
                double dPhi = i * dGoldenAngle;
                aOffsets.Add(new Vector3(
                    (float)(dRadius * dRho * Math.Cos(dPhi)), (float)(dRadius * dRho * Math.Sin(dPhi)), (float)(dRadius * dZ)));
            }
        }
        return [.. aOffsets];
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
// (01_01 §4.3 A) are NOT integrated here yet — open leg 00_07 HW.26 (gated G1–G4).
internal static class Zone1Anode
{
    // The gyroid-annulus inner radius: the monolithic bus-rod surface (01_01 §1.4). With no rod declared the
    // lattice reaches the axis — a synthetic in-test coupon, never a shipped part. Shared by the envelope
    // (porosity ref + clip) and the gyroid gradient core so the lattice annulus and the solid rod meet exactly.
    internal static float InnerRadiusMm(AnchorCem cem)
        => cem.BusRodDiameterMm > 0f ? cem.BusRodDiameterMm / 2f : 0f;

    // Solid pipe envelope (outer Ø + inner Ø) — also the porosity reference volume (the gyroid annulus only;
    // the solid bus rod is added in BuildMonolithic and is NOT part of the porosity measurement).
    public static Voxels Envelope(AnchorCem cem)
    {
        BasePipe oPipe = new(new LocalFrame(), cem.LengthMm, InnerRadiusMm(cem), cem.OuterDiameterMm / 2f);
        return oPipe.voxConstruct();
    }

    // Constant (v1) ONLY when there is no Rim taper AND sheet topology — `bGraded` ORs in `bNetwork`, so
    // every shipped anchor takes the graded generator today, taper or not.
    // An ABSENT Rim field means "equals core" (back-compat with v1 manifests). ⚠ Period keeps its `> 0`
    // sentinel because a period ≤ 0 is meaningless in every topology; the WALL param does not, because
    // on network it is a level and 0 / negative are ordinary values (Cem.cs).
    public static IImplicit Gyroid(AnchorCem cem)
    {
        float fPeriodRim = cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;
        float fWallRim = cem.GyroidWallParamRim ?? cem.GyroidWallParam;
        bool bNetwork = cem.Topology.Equals("network", StringComparison.OrdinalIgnoreCase);

        if (cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase))
            return new ZonedGyroid(
                (InnerRadiusMm(cem) + (cem.OuterDiameterMm / 2f)) / 2f,
                cem.GyroidPeriodMm, fPeriodRim, cem.GyroidWallParam);

        bool bGraded = fPeriodRim != cem.GyroidPeriodMm || fWallRim != cem.GyroidWallParam || bNetwork;

        IImplicit oField = bGraded
            ? new GradedCartesianGyroid(
                InnerRadiusMm(cem), cem.OuterDiameterMm / 2f,
                cem.GyroidPeriodMm, fPeriodRim,
                cem.GyroidWallParam, fWallRim, bNetwork)
            : new CartesianGyroid(cem.GyroidPeriodMm, cem.GyroidWallParam);

        // ⛔ OFF by default, and that is the whole point of the field existing: every shipped number
        //    was measured on the un-normalised field, so flipping this silently would move them all
        //    with nothing red. It is here to make the A/B MEASURABLE (00_07 HW.49); the switch is a
        //    ⚖️ that follows the measurement, never precedes it.
        return cem.NormaliseField
            ? new NormalisedField(oField, MathF.Min(cem.GyroidPeriodMm, fPeriodRim) / 200f)
            : oField;
    }

    // Build direction in the anode's OWN frame. z = 0 is the tree-side tip (AxialStack's datum: the Zone-2 sleeve and
    // the capsule sit above it), and 01_02 §1.6 prints the anode tip-DOWN, so the part grows away from z = 0: BD = +Z.
    // ⚖️ The orientation of the INTEGRATED Zone-1 body is an open verdict (00_07 HW.26 G4 · HW.23). Only a LOCAL reading
    //    of the downskin mode rides on this sign: on the infinite constant-period lattice a 2-fold screw of the gyroid
    //    maps +Z onto −Z, so a GLOBAL curve barely moves with it — "barely", because the graded, clipped annulus is not
    //    invariant under that screw (measured 2026-09-14, pine at period/12, downskin 0.45 mm: 48.646 % porous for +Z,
    //    48.613 % for −Z). Pinned by its physical consequence, never by its value (picogk #15).
    internal static readonly Vector3 BuildDirection = Vector3.UnitZ;

    // The part body a SHIFTED dilation sample may take metal from — the envelope `build` cuts, with its two ends.
    internal static Func<Vector3, bool> Body(AnchorCem cem)
    {
        float fRInner = InnerRadiusMm(cem), fROuter = cem.OuterDiameterMm / 2f, fLength = cem.LengthMm;
        return vecAt =>
        {
            float fR = MathF.Sqrt((vecAt.X * vecAt.X) + (vecAt.Y * vecAt.Y));
            return fR >= fRInner && fR <= fROuter && vecAt.Z >= 0f && vecAt.Z <= fLength;
        };
    }

    // The part's lattice dilated by one face offset (DilatedField) — the one composition the `fea --dilate` verb and
    // its pins share. Offset 0 returns the lattice's own sign everywhere: the identity the zero row is checked against.
    internal static IImplicit Dilated(AnchorCem cem, DilationMode mode, float fFaceOffsetMm)
        => new DilatedField(Gyroid(cem), Body(cem), DilatedField.Element(mode, fFaceOffsetMm, BuildDirection));

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
    // BoolAdd (gotcha #9 — never an SDF field left open at the bbox caps; the same split as MechanicalLock's solid shank).
    // A rod-less CEM (BusRodDiameterMm==0) returns the bare gyroid → back-compat with the v1 manifests.
    // The solid monolithic bus-rod core as voxels (01_01 §1.4) — ShapeKernel voxConstruct (gotcha #9,
    // never an open SDF field for a solid). Shared by BuildMonolithic (the part) + the verify
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
