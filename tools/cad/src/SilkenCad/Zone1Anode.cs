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
// (founder 2026-06-21; the constant-vs-graded fork has a BIOLOGICAL criterion, ⚖️ 2026-09-17 — 01_01 §5.5). Phase uses the LEAP-style
// coord/period(r): a spatially-varying frequency is not strictly periodic (cells distort slightly
// across the gradient) but stays bicontinuous → porosity is MEASURED per radial shell, never derived
// (gotcha #4). ⚠️ «Slightly» is FALSE BY HEIGHT — measured 2026-10-22 (`cellshape`, CellShape.cs, 01_01 §5.5): the
// phase gains ∇k·coord terms — in-plane up to r·k′(r) and, because Z is scaled by the same 2π/period(r), z·k′(r)
// along the axis — and the axial one SHEARS the cell in the r–z plane by γ = z·|P′|/P while keeping its volume, so the
// top of every period-graded SKU read about half its nominal along one axis at flat porosity. ⚖️ founder 2026-10-22
// (00_07 HW.33, option (в), canon 01_01 §5.5): the phase is graded IN PLANE only — θz takes ONE wavenumber, the RIM
// period's, chosen by `Zone1Anode.Gyroid` (a rule, not a CEM field). `fPeriodAxialMm` = 0 keeps the pre-verdict field
// (θz = k(r)·z), which exists only as the instrument's sheared reference (`CellShape.PreVerdictGyroid`). What no
// variant removes: the in-plane term ε = r·|P′|/P. Topology: sheet = a wall around the minimal surface (|eq|; stretch-dominated, more
// surface); network = one solid channel (one side of eq; bending-dominated, lower E) — the HW.33 axis.
internal sealed class GradedCartesianGyroid : IImplicit
{
    private readonly float _fRCore, _fRRim, _fPeriodCore, _fPeriodRim, _fWallCore, _fWallRim, _fKAxial;
    private readonly bool _bNetwork;

    public GradedCartesianGyroid(
        float fRCoreMm, float fRRimMm,
        float fPeriodCoreMm, float fPeriodRimMm,
        float fWallCore, float fWallRim,
        bool bNetwork, float fPeriodAxialMm)
    {
        _fRCore = fRCoreMm;
        _fRRim = fRRimMm;
        _fPeriodCore = fPeriodCoreMm;
        _fPeriodRim = fPeriodRimMm;
        _fWallCore = fWallCore;
        _fWallRim = fWallRim;
        _bNetwork = bNetwork;
        _fKAxial = fPeriodAxialMm > 0f ? 2f * MathF.PI / fPeriodAxialMm : 0f;
    }

    public float fSignedDistance(in Vector3 vecPt)
    {
        // Radial blend 0 (core/axis) → 1 (rim), from the cylindrical radius about the rod's Z axis.
        float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
        float fT = _fRRim > _fRCore ? Math.Clamp((fR - _fRCore) / (_fRRim - _fRCore), 0f, 1f) : 0f;
        float fPeriod = _fPeriodCore + ((_fPeriodRim - _fPeriodCore) * fT);
        float fWall = _fWallCore + ((_fWallRim - _fWallCore) * fT);
        float fFreq = 2f * MathF.PI / fPeriod;

        float fX = fFreq * vecPt.X, fY = fFreq * vecPt.Y, fZ = (_fKAxial > 0f ? _fKAxial : fFreq) * vecPt.Z;
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

// Zone-1 gyroid anode (01_01 §5): a gyroid Ti rod (Ø per CEM, founder Ø11), clipped from a
// BasePipe envelope. ⛔ The bus rod is NOT part of this printed body and has not been since the
// welded-wire verdict (⚖️ 2026-09-10, CAD applied 2026-09-18 — 00_07 HW.1/HW.34): canon 01_01 §3
// step 1 prints the anode WITHOUT a central rod and welds a drawn wire to its TOP FACE as its own
// operation, so a printed core here would be an STL describing a branch the founder removed.
// The wire lives in the ASSEMBLY (AxialStack), never in the part. Bicontinuous, orientation-
// agnostic (founder decision (б), HW.33). v2 = radially graded (period + porosity + topology),
// CEM-driven; a constant CEM (no Rim fields, sheet) renders the v1 uniform gyroid. The lock shank
// (barbs + groove, 01_01 §4.3) is NOT in `Build`: `BuildIntegrated` below is a second builder beside it, returning
// ONE fused body, and its header says what that step does not do (00_07 HW.26 G3 · G4).
internal static class Zone1Anode
{
    // The radius `build` cuts from: **0 — the lattice reaches the axis**. It was the bus-rod surface until
    // 2026-09-18, when the welded branch was applied: nothing is printed in the core, and a Ø1.0 bore would
    // be a functionless through-hole (trapped powder) that no verdict asks for — ⚖️ founder 2026-09-18 chose
    // «lattice to the axis» over «keep the bore» for exactly that reason (00_07 HW.1).
    // ⛔ The function stays — the envelope, the porosity reference, the gradient core, the topology grid, the
    // FE sampler, the per-shell radii and the drawing all read it, and the pin that they agree with what
    // `build` cuts is what keeps a reader from re-introducing a core privately. ⚠️ Declared ceiling: while it
    // returns a CONSTANT, that pin judges agreement on a constant — it guards the future divergence, not a
    // present one, and `cem` stays in the signature because the day a part declares a bore it must come from
    // the manifest, never from a second formula.
    // 🔴 MOVING THIS VALUE IS NOT A CLIPPING CHANGE — IT RESHAPES THE LATTICE EVERYWHERE, and the 2026-09-18
    //    application proved it by accident (mechanism measured 2026-09-20, 00_07 HW.1 → canon 01_02 §6). It is
    //    the LEFT EDGE of the radial map in BOTH generators: `GradedCartesianGyroid` normalises by
    //    (r − r_core)/(r_rim − r_core), so every physical radius re-maps to a different PERIOD, and
    //    `ZonedGyroid` takes its zone boundary as (r_core + R)/2, which moved 3.00 → 2.75 mm. Measured
    //    consequence of 0.5 → 0: six network SKUs' specific surface fell 0.4–1.1 %, and `stepped`'s sub-floor
    //    share ROSE 71.0 → 75.4 % — the rim zone (whose sheet wall is below the print floor) simply got bigger.
    //    ⛔ So a verdict about the PART (no printed core) silently re-decided the pore-gradient profile of all
    //    seven SKUs (01_01 §5.5). Change it only WITH a re-measure of every golden and a line saying which
    //    profile the new map produces.
    internal static float InnerRadiusMm(AnchorCem cem) => 0f;

    // Solid pipe envelope (outer Ø + inner Ø = 0 ⇒ a full cylinder) — also the porosity reference volume.
    // ⚠️ Since 2026-09-18 it is the WHOLE cross-section: the bus rod left the part, so there is no core to
    // exclude and porosity is measured against the full Ø, not against an annulus.
    public static Voxels Envelope(AnchorCem cem)
    {
        BasePipe oPipe = new(new LocalFrame(), cem.LengthMm, InnerRadiusMm(cem), cem.OuterDiameterMm / 2f);
        return oPipe.voxConstruct();
    }

    // The one period the shipped field repeats with along z — read by Gyroid() below and by the sampler's phase-lock
    // check (VoxelFea.AxialPhaseLockCells), so the two cannot disagree: the rim's (⚖️ HW.33 (в)), which on a
    // constant-period part is the one period. A STEPPED part has two (each zone keeps its own) → 0, no single period.
    public static float AxialPeriodMm(AnchorCem cem)
        => cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase) ? 0f
         : cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;

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

        // ⚖️ HW.33 (в), 2026-10-22: ONE axial period, the rim's — so the cell no longer shears with height. On a part
        // whose period is constant this is the same field as before (the axial wavenumber was already one number).
        IImplicit oField = bGraded
            ? new GradedCartesianGyroid(
                InnerRadiusMm(cem), cem.OuterDiameterMm / 2f,
                cem.GyroidPeriodMm, fPeriodRim,
                cem.GyroidWallParam, fWallRim, bNetwork, fPeriodAxialMm: AxialPeriodMm(cem))
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
    // ⚖️ The orientation of the INTEGRATED Zone-1 body is an open verdict — and its ONE home is 00_07 HW.26 G4.
    //    ⛔ Do not read HW.23 as a second home for it: that item RATIFIED and APPLIED its own orientation verdict on
    //    2026-09-18 (fatigue SPECIMENS in two build orientations; 01_02 §1.6 lost the "axial wind loads" ground), so
    //    what is open there is nothing about this sign. Only a LOCAL reading
    //    of the downskin mode rides on this sign: on the infinite constant-period lattice a 2-fold screw of the gyroid
    //    maps +Z onto −Z, so a GLOBAL curve barely moves with it — "barely", because the graded, clipped body is not
    //    invariant under that screw (measured 2026-09-14 on the then-annular part, pine at period/12, downskin 0.45 mm: 48.646 % porous for +Z,
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

    // The full standalone part IS the gyroid lattice to the axis — nothing is added to it. `BusRod`/`BuildMonolithic`
    // were removed on 2026-09-18 with the branch they modelled (the printed core): keeping a rod body here
    // «for the render» would put the removed branch back on every sheet and every FE run that reads the part.
    public static Voxels Build(AnchorCem cem) => Anode(cem, Envelope(cem));

    // ── The INTEGRATED Zone-1 body: the gyroid ∪ its lock's solid shank (00_07 HW.26 G3) ──
    // A second BUILDER beside `Build`, never inside it, and what it returns is ONE fused body: `Build` · `Envelope` ·
    // `Gyroid` · `Body` stay the lattice alone, so porosity, connectivity, the FE samplers, the goldens and the
    // canon-sync gates go on measuring the same object.
    //
    // Frames. The shank stands on the gyroid's top face, z ∈ [L, L + S], and the PEEK sleeve is pressed on from ABOVE
    // (01_01 §3 step 4; AxialStack.SleeveBottomZMm = L): the end that enters the PEEK first is the body's TOP face,
    // z = L + S. In the lock's frame that end is local z = 0, the one its shallow α ramp faces (MechanicalLock). The two
    // axes run OPPOSITE ways, so the shank is placed by a 180° turn about a transverse axis plus a shift. A plain shift
    // would put the steep β face first into the PEEK — the reversed ratchet the flange once shipped (picogk #15). (A
    // mirror draws the same profile with the winding reversed; measured once, the voxeliser built the same body from
    // it — it is kept out because the turn is what the assembly does, not because the mirror showed a fault.)
    //
    // ⛔ What this does NOT do:
    //   • an anode whose Ø differs from the shank's is REFUSED, not stepped: the stop is press tooling, never a part
    //     feature (⚖️ 2026-10-12), and the shank · sleeve · step of the Ø10 / Ø12 / Ø13 SKUs is an open founder
    //     decision (00_07 HW.26 G3);
    //   • the print orientation of this body is open (00_07 HW.26 G4, waiting on the print bureaus' answer) — nothing
    //     here chooses one or adds a support;
    //   • no anchor manifest NAMES its lock yet: the caller hands the pair in, and nothing checks it is the intended one;
    //   • the lattice ⊥ solid junction at z = L is a flat butt joint with no transition and no model (00_07 HW.23);
    //   • the CLI builds it at the FINER of the two manifests' voxels, so the gyroid in this STL is rendered on another
    //     grid than the one its golden, `verify` and porosity were measured on — Golden.cs compares no run at another
    //     voxel, so this body has NO regression baseline;
    //   • the groove is modelled as finished geometry — CNC after printing (01_01 §4.3 B; the convention of
    //     Validation.MeasureLock): the STL shows the part after machining, not a printed overhang;
    //   • no xUnit sees the BUILT body (CI has no voxel runtime). The pins hold the profile and the placement map; the
    //     body is judged where it is written — Program.BuildIntegrated reads the mesh and refuses to write it on a
    //     finding of IntegratedProfileFindings / IntegratedSeamFindings below; once both manifests are parsed, a run
    //     that fails leaves no STL under the body's name (before that — a path that does not exist, a manifest of
    //     the wrong kind — an earlier file stays). No gate runs that verb (neither cad_smoke nor pre-push builds a
    //     mesh): deleting the call, or its `return 1`, reds nothing. What the check's tolerances let through is a
    //     pinned table — MechanicalLockTests.The_Mesh_Check_Lets_Through_What_Its_Tolerances_Declare.

    // The body's top face — where the bus wire is welded and the sleeve arrives.
    internal static float IntegratedLengthMm(AnchorCem anode, MechanicalLockCem lockCem)
        => anode.LengthMm + lockCem.ShankLengthMm;

    // The ONE home of the reversal: anode-frame z → the lock's local z. It is its own inverse, so ShankPlacement
    // carries the lock's vertices INTO the anode frame through this same line. That BuildIntegrated really places by
    // it is nothing this line can promise — the mesh check in Program.BuildIntegrated holds the built body to it.
    internal static float LockLocalZ(AnchorCem anode, MechanicalLockCem lockCem, float fZ)
        => IntegratedLengthMm(anode, lockCem) - fZ;

    private static void RequireShankOfAnodeDiameter(AnchorCem anode, MechanicalLockCem lockCem)
    {
        if (anode.OuterDiameterMm != lockCem.ShankDiameterMm)
            throw new InvalidDataException(
                $"{anode.Name} is Ø{anode.OuterDiameterMm:0.###} mm and the lock shank {lockCem.Name} is " +
                $"Ø{lockCem.ShankDiameterMm:0.###} mm — the gyroid-to-shank transition of a SKU whose Ø differs from its " +
                "shank's is not specified (no step, no sleeve, no groove size: an open founder decision, 00_07 HW.26 G3), " +
                "so no integrated body is built");
    }

    // Lock-local vertex → anode frame: (x, y, z) → (x, −y, LockLocalZ(z)), a proper rotation (det +1) plus the shift —
    // and its own inverse, which is how the mesh check reads a built vertex back into the lock's coordinates.
    // Acquiring it is the refusal: BuildIntegrated cannot place a shank without passing the Ø check.
    internal static Func<Vector3, Vector3> ShankPlacement(AnchorCem anode, MechanicalLockCem lockCem)
    {
        RequireShankOfAnodeDiameter(anode, lockCem);
        return v => new Vector3(v.X, -v.Y, LockLocalZ(anode, lockCem, v.Z));
    }

    // Outer radius of the integrated body along the ANODE's z — pure maths, for the pins (no voxels): the lattice's
    // ENVELOPE radius over the gyroid (the lattice is a callout, never a contour — 01_02 §6), the lock's own R(z_l)
    // over the shank (barbs, and the groove where MechanicalLock.HasGroove), 0 outside the body.
    internal static Func<float, float> IntegratedProfile(AnchorCem anode, MechanicalLockCem lockCem)
    {
        RequireShankOfAnodeDiameter(anode, lockCem);
        var oShank = new MechanicalLockShank(lockCem);
        float fJunction = anode.LengthMm, fTop = IntegratedLengthMm(anode, lockCem), fREnvelope = anode.OuterDiameterMm / 2f;
        return fZ => fZ < 0f || fZ > fTop ? 0f
                   : fZ < fJunction ? fREnvelope
                   : oShank.ProfileRadius(LockLocalZ(anode, lockCem, fZ));
    }

    // The lattice exactly as `Build` makes it, plus the lock exactly as MechanicalLock.Build makes it (its numbers,
    // its groove flag — nothing is copied here), turned into the anode frame.
    public static Voxels BuildIntegrated(AnchorCem anode, MechanicalLockCem lockCem)
    {
        Func<Vector3, Vector3> fnPlace = ShankPlacement(anode, lockCem);
        Voxels voxBody = Build(anode);
        voxBody.BoolAdd(MeshUtility.voxApplyTransformation(MechanicalLock.Build(lockCem), v => fnPlace(v)));
        return voxBody;
    }

    // ── The check of the BUILT mesh. Reading the mesh is Program.BuildIntegrated's; the comparison is pure, so xUnit
    //    pins it without voxels. The shank is read two ways: per LAYER — the largest and the smallest radius any vertex
    //    of the layer has, layers one voxel thick and counted DOWN from the top face, the way the sleeve meets them:
    //    layer j spans the depth [j·layer, (j + 1)·layer) — and, for the crests, per row BY AZIMUTH
    //    (MechanicalLock.ReadCrestVertex · CrestFindings: a crest low on part of the circle hides from both layer
    //    extremes, behind the whole part of the tooth and under the lower bound its steep flank brings). ──

    // Tolerances, in layers (= voxels). A POSITION along the axis gets 2: a meshed face lands within a voxel of its
    // nominal, and the layer that straddles it reads either side — the `2·voxel` Resolution.cs calls "represented".
    // A RADIUS gets 1: a sharp edge meshes rounded, short of its nominal by a fraction of a voxel. The room a SOUND
    // mesh keeps, measured over the band of voxels the verb admits (0.03–0.063 mm, pine and mangrove, 2026-11-15):
    // the crest by azimuth 0.007–0.025 mm above its floor — the least at voxels 0.032–0.034 — and the layer reading
    // 0.009–0.054 mm, the least on mangrove at 0.035; at the shipped 0.05 they keep 0.011 and 0.043. A false red, if
    // one comes, comes from the crest reading first.
    // ⛔ What these let through is not restated here: MechanicalLockTests
    //    .The_Mesh_Check_Lets_Through_What_Its_Tolerances_Declare holds the table — each departure at the edge that
    //    still passes, beside the next step that reds — and its header names what no reading here can show at all.
    internal const int IntegratedCheckAxialToleranceLayers = 2;
    internal const float IntegratedCheckRadialToleranceLayers = 1f;

    internal static int ShankLayerCount(MechanicalLockCem lockCem, float fLayerMm)
        => (int)MathF.Ceiling((lockCem.ShankLengthMm / fLayerMm) - 1e-3f);

    // Feeds one mesh vertex (anode-frame z, radius) into the per-layer extremes; a vertex below the junction is the
    // lattice's and is skipped (the lattice is no body of revolution).
    // ⚠️ A vertex within a thousandth of a layer of a boundary counts for BOTH layers. On a vertical wall every mesh
    //    vertex lies on a voxel plane, and when those planes fall ON the layer boundaries — an anode whose length is
    //    half a voxel off the grid; measured at L = 40.025, where two layers came back with no vertex and the build
    //    red for nothing — float noise drops each plane into one layer or the other.
    internal static void ReadShankVertex(AnchorCem anode, MechanicalLockCem lockCem, float fLayerMm, float fZ, float fR,
                                         float[] aLayerMax, float[] aLayerMin)
    {
        if (fZ < anode.LengthMm) return;
        float fU = (IntegratedLengthMm(anode, lockCem) - fZ) / fLayerMm;
        int j = (int)MathF.Floor(fU);
        Feed(j);
        if (fU - j < 1e-3f) Feed(j - 1);
        else if (fU - j > 1f - 1e-3f) Feed(j + 1);

        void Feed(int k)
        {
            k = Math.Clamp(k, 0, aLayerMax.Length - 1);
            aLayerMax[k] = MathF.Max(aLayerMax[k], fR);
            aLayerMin[k] = MathF.Min(aLayerMin[k], fR);
        }
    }

    // IntegratedProfile as its per-layer maximum — the analytic side of the comparison.
    internal static float[] ShankLayerMaxRadius(AnchorCem anode, MechanicalLockCem lockCem, float fLayerMm)
    {
        const int nSub = 20;
        Func<float, float> fnRadiusAtZ = IntegratedProfile(anode, lockCem);
        float fTop = IntegratedLengthMm(anode, lockCem);
        var aMax = new float[ShankLayerCount(lockCem, fLayerMm)];
        for (int j = 0; j < aMax.Length; j++)
            for (int i = 0; i <= nSub; i++)
                aMax[j] = MathF.Max(aMax[j], fnRadiusAtZ(MathF.Max(fTop - ((j + ((float)i / nSub)) * fLayerMm), anode.LengthMm)));
        return aMax;
    }

    private static float FlankRunMm(MechanicalLockCem lockCem, float fAngleDeg)
        => lockCem.BarbHeightMm / MathF.Tan(fAngleDeg * MathF.PI / 180f);

    // Whether a layer this thick can tell the shallow ramp from the steep face on a mesh (reading 1 below). It follows
    // from the two manifests alone, so Program refuses a too-coarse build BEFORE the runtime starts — the reading
    // itself is never asked to judge such a layer.
    internal static bool LayerResolvesRatchet(MechanicalLockCem lockCem, float fLayerMm)
        => fLayerMm <= (FlankRunMm(lockCem, lockCem.LeadAngleDeg) - FlankRunMm(lockCem, lockCem.TrailAngleDeg)) / 6f;

    // The mesh's shank against what the two manifests say. A shank layer with no vertex at all is its own finding and
    // ends the reading — there is no shank there to judge. Otherwise three readings:
    //   1. the RATCHET, by its physical consequence and on the mesh alone (picogk #15): walking down from the top face,
    //      the first tooth must RISE over a longer run than it FALLS — the shallow α ramp meets the PEEK first. The
    //      walk starts 2 layers above where IntegratedProfile puts the first tooth (a bump nearer the top face is
    //      reading 2's business), and a layer is tooth metal when its largest radius exceeds the MEDIAN layer's by
    //      more than the radial tolerance — the median being the mesh's own plain shank, so a shank evenly too thick
    //      or too thin is a radius finding and not a tooth. ⚠️ Not «rise against the α/β midpoint», the analytic
    //      pins' form: a mesh rounds the foot and the crest of the steep flank, so that flank over-reads by up to 3
    //      layers and lands within a layer of the midpoint (measured on a deliberately shifted build);
    //   2. EVERY LAYER against IntegratedProfile: nothing may stick out beyond the largest analytic radius of its
    //      ± 2 layers, nothing may be cut in below the smallest. Findings are grouped by what they sit at — a barb
    //      row, the groove band, the plain shank. The smallest radius is not read on the two end layers: they hold
    //      the top face and the seam face;
    //   3. every tooth's CREST, in every sector of the circle (MechanicalLock.CrestFindings).
    internal static (string Summary, IReadOnlyList<string> Findings) IntegratedProfileFindings(
        AnchorCem anode, MechanicalLockCem lockCem, float fLayerMm, float[] aMeshMax, float[] aMeshMin, float[,] aCrest)
    {
        float[] aAnalytic = ShankLayerMaxRadius(anode, lockCem, fLayerMm);
        int n = aAnalytic.Length;
        if (aMeshMax.Length != n || aMeshMin.Length != n)
            return ("", [$"the mesh profile has {aMeshMax.Length} / {aMeshMin.Length} layers, the shank has {n} at {fLayerMm:0.###} mm"]);

        const int nAxial = IntegratedCheckAxialToleranceLayers;
        float fTop = IntegratedLengthMm(anode, lockCem), fRShank = lockCem.ShankDiameterMm / 2f;
        float fTol = IntegratedCheckRadialToleranceLayers * fLayerMm;
        float fLead = FlankRunMm(lockCem, lockCem.LeadAngleDeg), fTrail = FlankRunMm(lockCem, lockCem.TrailAngleDeg);
        string At(int j) => $"{j * fLayerMm:F2}…{(j + 1) * fLayerMm:F2} mm below the top face (z {fTop - ((j + 1) * fLayerMm):F2}…{fTop - (j * fLayerMm):F2})";

        int nEmpty = aMeshMax.Count(r => r <= 0f);
        if (nEmpty > 0)
            return ("", [$"{nEmpty} of the {n} shank layers carry NO mesh at all (the first is {At(Array.FindIndex(aMeshMax, r => r <= 0f))}) — " +
                         "there is no shank there, so nothing else is read"]);

        var aFindings = new List<string>();

        // 1. Ratchet direction.
        float fRise = 0f, fFall = 0f;
        int jFirstAnalytic = Array.FindIndex(aAnalytic, r => r > fRShank + fTol);
        if (jFirstAnalytic >= 0)
        {
            float[] aSorted = [.. aMeshMax];
            Array.Sort(aSorted);
            float fMetal = aSorted[n / 2] + fTol;
            int j0 = Math.Max(0, jFirstAnalytic - nAxial);
            while (j0 < n && aMeshMax[j0] <= fMetal) j0++;
            if (j0 == n)
            {
                aFindings.Add("the mesh carries NO barb at or below where IntegratedProfile puts the first one");
            }
            else
            {
                int jCrest = j0;
                while (jCrest + 1 < n && aMeshMax[jCrest + 1] >= aMeshMax[jCrest] - (0.1f * fLayerMm)) jCrest++;
                int jEnd = jCrest;
                while (jEnd + 1 < n && aMeshMax[jEnd + 1] > fMetal) jEnd++;
                fRise = (jCrest + 1 - j0) * fLayerMm;
                fFall = (jEnd - jCrest) * fLayerMm;
                if (fRise <= fFall)
                    aFindings.Add($"the ratchet is REVERSED on the built mesh: from the top face the first tooth (at {j0 * fLayerMm:F2} mm) " +
                                  $"rises over {fRise:F2} mm and falls over {fFall:F2} — its steep face meets the PEEK first (01_01 §4.3 A)");
            }
        }

        // 2. Every layer. Zone of a layer = the analytic feature within the axial tolerance of it.
        var aRowOf = new int[n];   // 0 = no tooth here, k = barb row k counted from the top face
        for (int j = 0, nRow = 0; j < n; j++)
        {
            if (aAnalytic[j] <= fRShank + fTol) continue;
            if (j == 0 || aRowOf[j - 1] == 0) nRow++;
            aRowOf[j] = nRow;
        }
        string Zone(int j)
        {
            int jLo = Math.Max(0, j - nAxial), jHi = Math.Min(n - 1, j + nAxial);
            for (int k = jLo; k <= jHi; k++) if (aAnalytic[k] < fRShank - fTol) return "the groove band";
            for (int k = jLo; k <= jHi; k++) if (aRowOf[k] > 0) return $"barb row {aRowOf[k]}";
            return "the plain shank";
        }
        var oWorst = new Dictionary<string, (float Excess, string Text)>();
        float fTightest = float.MaxValue;
        void Note(string strZone, float fExcess, string strText)
        {
            fTightest = MathF.Min(fTightest, -fExcess);
            if (fExcess > 0f && (!oWorst.TryGetValue(strZone, out var w) || fExcess > w.Excess)) oWorst[strZone] = (fExcess, strText);
        }
        for (int j = 0; j < n; j++)
        {
            int jLo = Math.Max(0, j - nAxial), jHi = Math.Min(n - 1, j + nAxial);
            float fMin = float.MaxValue, fMax = float.MinValue;
            for (int k = jLo; k <= jHi; k++) { fMin = MathF.Min(fMin, aAnalytic[k]); fMax = MathF.Max(fMax, aAnalytic[k]); }
            float fInner = j == 0 || j == n - 1 ? aMeshMax[j] : aMeshMin[j];
            Note(Zone(j), aMeshMax[j] - fMax - fTol, $"metal out to r {aMeshMax[j]:F3} where the profile allows {fMax:F3} at {At(j)}");
            Note(Zone(j), fMin - fTol - fInner, $"metal only to r {fInner:F3} where the profile asks {fMin:F3} at {At(j)}");
        }
        foreach ((string strZone, (float fExcess, string strText)) in oWorst.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            aFindings.Add($"the built mesh leaves IntegratedProfile at {strZone} by {fExcess:F3} mm beyond tolerance: {strText}");

        // 3. Every crest, by azimuth.
        (string strCrests, IReadOnlyList<string> aCrestFindings) = MechanicalLock.CrestFindings(lockCem, fLayerMm, aCrest);
        aFindings.AddRange(aCrestFindings.Select(f => $"the built mesh leaves IntegratedProfile at {f}"));

        return ($"shank profile, {n} layers of {fLayerMm:0.###} mm: the first tooth from the top face rises over {fRise:F2} mm and " +
                $"falls over {fFall:F2} (α ramp {fLead:F3} · β face {fTrail:F3}) · the layer nearest its tolerance keeps " +
                $"{fTightest:F3} mm · {strCrests}", aFindings);
    }

    // The seam at z = L stands on COINCIDENT faces — two level sets that are both ≈ 0 there — so that the union fused
    // is measured, not assumed, in two readings:
    //   • the largest connected surface must reach from the tree-side tip to the top face (a shank that did not fuse
    //     leaves two);
    //   • no OTHER surface may rise above the seam plane by more than half a voxel: an inner shell of the shank, a
    //     bubble crossing the plane, a piece torn off above it.
    // Loose surfaces that stay below the plane are the clipped lattice's own crumbs — a lattice built WITHOUT a shank
    // carries them right up to its top face — and are only counted.
    // ⛔ Ceilings: EVERYTHING that lies wholly below the seam plane passes, at any depth — a void, a detached piece, a
    //    crumb: this reading cannot tell them apart and judges none of them; and connectivity is by SHARED VERTICES,
    //    so a membrane inside the metal that shares its vertices with the outer surface is invisible here.
    // Why components and not the shank's volume contribution (picogk #9b): volume is additive whether or not the faces
    // fuse, so it cannot see a seam — and a shank that added nothing shows in the profile above.
    internal static (string Summary, IReadOnlyList<string> Findings) IntegratedSeamFindings(
        AnchorCem anode, MechanicalLockCem lockCem, float fVoxelMm, float[] aVertexZ, int[] aTriangleVertices)
    {
        int[] aParent = new int[aVertexZ.Length];
        for (int i = 0; i < aParent.Length; i++) aParent[i] = i;
        int Root(int i)
        {
            while (aParent[i] != i) { aParent[i] = aParent[aParent[i]]; i = aParent[i]; }
            return i;
        }
        for (int t = 0; t < aTriangleVertices.Length; t += 3)
        {
            int rA = Root(aTriangleVertices[t]);
            aParent[Root(aTriangleVertices[t + 1])] = rA;
            aParent[Root(aTriangleVertices[t + 2])] = rA;
        }

        var oSurfaces = new Dictionary<int, (int Triangles, float ZMin, float ZMax)>();
        for (int t = 0; t < aTriangleVertices.Length; t += 3)
        {
            int r = Root(aTriangleVertices[t]);
            (int nTris, float fLo, float fHi) = oSurfaces.TryGetValue(r, out var s) ? s : (0, float.MaxValue, float.MinValue);
            for (int k = 0; k < 3; k++)
            {
                float fZ = aVertexZ[aTriangleVertices[t + k]];
                fLo = MathF.Min(fLo, fZ);
                fHi = MathF.Max(fHi, fZ);
            }
            oSurfaces[r] = (nTris + 1, fLo, fHi);
        }
        if (oSurfaces.Count == 0) return ("", ["the mesh has no triangles"]);

        var aFindings = new List<string>();
        float fTop = IntegratedLengthMm(anode, lockCem), fTol = IntegratedCheckAxialToleranceLayers * fVoxelMm;
        (int iBody, var oBody) = oSurfaces.MaxBy(kv => kv.Value.Triangles);
        if (oBody.ZMin > fTol || oBody.ZMax < fTop - fTol)
            aFindings.Add($"the lattice and the shank are NOT one connected surface: the largest ({oBody.Triangles:N0} triangles) spans " +
                          $"z {oBody.ZMin:F2}…{oBody.ZMax:F2} mm of 0…{fTop:F2} — the seam at z = {anode.LengthMm:F2} did not fuse");
        var aLoose = oSurfaces.Where(kv => kv.Key != iBody).Select(kv => kv.Value).ToList();
        var aAbove = aLoose.Where(s => s.ZMax > anode.LengthMm + (0.5f * fVoxelMm)).ToList();
        if (aAbove.Count > 0)
            aFindings.Add($"{aAbove.Count} detached surface(s) of {aAbove.Sum(s => s.Triangles):N0} triangles rise above the seam plane " +
                          $"(z {aAbove.Min(s => s.ZMin):F2}…{aAbove.Max(s => s.ZMax):F2} mm) — an unfused shank, an inner shell or a bubble across the seam");

        return ($"{oSurfaces.Count} surface component(s): the body ({oBody.Triangles:N0} triangles, z {oBody.ZMin:F2}…{oBody.ZMax:F2}) + " +
                $"{aLoose.Count} loose, {aAbove.Count} of them above the seam plane ({aLoose.Sum(s => s.Triangles):N0} triangles" +
                (aLoose.Count > 0 ? $", z ≤ {aLoose.Max(s => s.ZMax):F2}" : "") + ")", aFindings);
    }
}
