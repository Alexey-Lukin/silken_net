// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;

namespace SilkenCad;

// Cell SHAPE of a lattice by height and radius — the line-intercept FABRIC (00_07 HW.33).
//
// 🔴 Why porosity cannot answer this. `GradedCartesianGyroid` scales all three coordinates by 2π/P(r), so its phase map
//    θ = k(r)·p has the Jacobian J = k·I + p ⊗ k′(r)·r̂, with r̂ = ∇r — in the local frame (r̂, φ̂, ẑ), rows being
//    θ-space components rotated into it:
//        ⎡ k + r·k′   0   0 ⎤
//    J = ⎢    0       k   0 ⎥
//        ⎣  z·k′      0   k ⎦
//    The cell map is F = k_nom·J⁻¹: a radial COMPRESSION by 1/(1 + ε), ε = r·k′/k = r·|P′|/P, followed by a SIMPLE SHEAR
//    of amount γ = z·|k′|/k = z·|P′|/P — shear direction ẑ, glide planes r = const — which grows from z = 0.
//    ⛔ Two inferences that do NOT follow (both were written here, measured and corrected 2026-10-22):
//      · det J = k²·(k + r·k′) is z-independent, so the cell VOLUME (cells per mm³) is the same at every height — that
//        is NOT why porosity is flat. A phase fraction survives ANY locally affine map whatever its det; porosity is
//        flat because the wall LEVEL depends on r alone. A map with z-dependent det would keep it flat too.
//      · the principal stretches are NOT the simple shear's √(1+γ²/4) ± γ/2: ε is 0.20–0.27 on the shipped parts, and
//        the shear factor alone overstates the elongation by ~13 % (pine top 2.11 against the full map's 1.83). Quote
//        stretches from the FULL J (`PredictedStretches`), never from the shear amount.
//    What survives, and is the point: a distortion that keeps porosity while changing pore and ligament is exactly what
//    `Connectivity.AxialProfile` cannot see.
//
// What this measures. Probe lines through the FIELD (not a voxel grid): along a direction d, the density of phase
//    boundaries crossed per mm, P_L(d), and the solid fraction V_V. Under a linear phase map the EXACT relation is
//    P_L(d) = |J·d| · f(Ĵd), where f(u) is the θ-space line-intercept density (Cauchy: S_V⟨|n·u|⟩) along the unit
//    direction J·d points at. f is constant only for an ISOTROPIC reference; the network gyroid's is cubic (measured at
//    level −0.45: 0.2492 crossings/rad along a cube axis, 0.2278 along a face diagonal, 0.2333 along a body diagonal,
//    0.2367 as the directional mean). Treating f as constant makes P_L² a QUADRATIC FORM dᵀQd, Q = c²·JᵀJ; fitting Q
//    over a hemisphere of directions gives the principal axes of the cell (its eigenvectors) and the squared crossing
//    densities along them (its eigenvalues). The mean chord of a phase along an axis is 2·(that phase's volume
//    fraction)/P_L — the stereological pore and ligament size along that axis (Underwood's intercept relations; the
//    mean-intercept-length fabric of bone morphometry). The same lines give specific surface, S_V = 2·⟨P_L⟩.
//
// ⚠️ DECLARED CEILINGS.
//   • A mean chord is NOT µCT's local thickness (the largest inscribed sphere): it is a size along a DIRECTION, and the
//     minimum neck of an inclined ligament is seen by neither. The number that carries meaning is RELATIVE — the same
//     instrument on the same cell of a constant-period field at that radius (the nominal, `Nominal`). A chord ratio is
//     the stretch times a volume-fraction ratio, so on a part with flat porosity it RESTATES the stretch and is not a
//     second, independent reading.
//   • 🔴 The instrument's FLOOR is SAMPLING, not the lattice's cubic anisotropy — measured 2026-10-22 against the exact
//     shear pin (CellShapeTests, γ = 1): at 400 centres a single stretch moves by up to ~8 %, at the caches' 1500 by
//     ~5 %, and at 6000 centres or an 8 mm probe the pin comes within ~1.3 % of exact on every axis. The cubic term
//     itself leaks ≤ ~1.5 % into the second-order fit (it is fourth-order, and the fit sees it only through the
//     direction map and least-squares aliasing on 32 directions), and it reads cube axes ABOVE the directional mean,
//     not below. A constant lattice reads DA 1.00–1.08 at these settings, so a DA under ~1.08 is indistinguishable from
//     isotropic, and differences smaller than the floor are not results. `FitResidual` carries what the form cannot fit.
//   • A feature thinner than the probe step can be crossed unseen; the step is a fraction of the finest period.
//   • 🔴 Near the AXIS the field itself is not affine: θ_z = k(|x⊥|)·z is a CONE, so J is undefined at r = 0 for z > 0
//     and the phase curvature z·k′/r grows inward (≈ 3.1 rad/mm² at the pine core shell's mean radius against ≈ 1.1 at
//     the outer one). A probe of one period there sweeps radians of non-linear phase, so a LOCAL fabric does not exist
//     and the first-order map does not describe it. Hence the probe is capped at the distance to the axis
//     (`Measure`'s `bCapProbeAtAxis`) and the core shell's rows are reported but kept OUT of the headline
//     measured-vs-predicted gap: with shorter probes the core-top gap fell 13.7 % → 8.8 % → 2.7 %, i.e. most of it was
//     the probe, not the part.
//   • 🔴 Outside the core the residual gap is ONE-SIGNED: the measurement reads 4–8 % LESS distortion than the
//     first-order map (compressed axis above the prediction, elongated below it, growing with height). More centres do
//     not remove it; it is cubic f (≤ ~3 %), rim clipping (~1 %) and commensurability. So a measured stretch is, if
//     anything, an UNDER-reading of the distortion.
//   • A probe counts only its stretch INSIDE the body: past the rim the graded period clamps (k′ = 0, an undistorted
//     lattice), so an unclipped probe would average the two.
internal static class CellShape
{
    // A hemisphere of probe directions is enough: P_L(d) = P_L(−d).
    internal const int DirectionCount = 32;

    internal readonly record struct Cell(float ZLoMm, float ZHiMm, float RLoMm, float RHiMm)
    {
        public float ZMidMm => 0.5f * (ZLoMm + ZHiMm);
        // Area-weighted mean radius of the annulus — where an area-uniform centre lands on average.
        public float RMeanMm => (2f / 3f) * ((RHiMm * RHiMm * RHiMm) - (RLoMm * RLoMm * RLoMm))
                                / MathF.Max((RHiMm * RHiMm) - (RLoMm * RLoMm), 1e-9f);
    }

    // The measurement frame: Cylindrical = (r̂, φ̂, ẑ) at each probe centre — the frame the graded J is diagonal-plus-
    // shear in; Cartesian = the global (x̂, ŷ, ẑ) — the frame an explicit affine map is written in (the analytic pin).
    internal enum Frame { Cylindrical, Cartesian }

    internal sealed record Fabric(
        double SolidFraction,
        double[] PrincipalPlPerMm,  // √eig(Q), DESCENDING — the most compressed axis first
        Vector3[] PrincipalAxes,    // matching eigenvectors, in the measurement frame
        double FitResidual,         // RMS of (dᵀQd − P_L²) over the directions, relative to the mean P_L²
        double DirectionalMeanPlPerMm, // ⟨P_L⟩ over the probe directions, un-fitted — S_V = 2·this
        long Crossings,
        double ProbedMm,
        bool ProbeCappedAtAxis)     // some centre's probe was shortened to its distance from the axis (header, core shell)
    {
        public double DegreeOfAnisotropy => PrincipalPlPerMm[0] / PrincipalPlPerMm[2];
        // The isotropic-equivalent crossing density: the geometric mean keeps a volume-preserving map at its nominal.
        public double MeanPlPerMm => Math.Cbrt(PrincipalPlPerMm[0] * PrincipalPlPerMm[1] * PrincipalPlPerMm[2]);
        public double SolidChordMm(int i) => 2.0 * SolidFraction / PrincipalPlPerMm[i];
        public double PoreChordMm(int i) => 2.0 * (1.0 - SolidFraction) / PrincipalPlPerMm[i];
        /// <summary>Specific surface from the same probe lines: S_V = 2·⟨P_L⟩ (mm²/mm³ of the PROBED region).</summary>
        public double SpecificSurfacePerMm => 2.0 * DirectionalMeanPlPerMm;

        /// <summary>
        /// The cell's principal stretches against a NOMINAL fabric, ASCENDING (index 0 = the most compressed axis) —
        /// ⛔ the ONE home of the convention: both the `cellshape` verb and its pins read it here, because an inverted
        /// copy in the verb was invisible to every test (adversary, 2026-10-22). A pure rotation reads 1 on every axis
        /// and the product is 1/det(J/k_nom), so a volume-keeping map keeps ∏λ = 1.
        /// </summary>
        public double[] StretchesAgainst(Fabric nominal)
            => [.. PrincipalPlPerMm.Select(pl => nominal.MeanPlPerMm / pl)];
    }

    /// <param name="nSeedOffset">
    /// Shifts this cell's R3 sample sequence. ⛔ Load-bearing: with one sequence for every cell, two cells of a
    /// CONSTANT-period lattice whose bins are an integer number of periods apart sample the SAME phases point for
    /// point — measured on the period-constant control, whose eight bins were four distinct samples (adversary,
    /// 2026-10-22; the class is picogk gotcha #16). Pass a per-cell offset and no two cells share phases.
    /// </param>
    /// <param name="bCapProbeAtAxis">
    /// Shortens each centre's probe to its own distance from the axis, so no probe reaches r = 0. The graded phase is a
    /// CONE about the axis (header), so a one-period probe in the core shell sweeps radians of non-linear phase and
    /// reads a local fabric that does not exist. Off for a Cartesian/affine reference, where there is no cone.
    /// </param>
    public static Fabric Measure(
        IImplicit field, Cell cell, Func<Vector3, bool> fnInBody,
        float fProbeMm, float fStepMm, int nCentres, Frame frame = Frame.Cylindrical,
        int nSeedOffset = 0, bool bCapProbeAtAxis = false)
    {
        Vector3[] aDirs = Hemisphere(DirectionCount);
        var aCross = new long[aDirs.Length];
        var aPairs = new long[aDirs.Length];
        long nSolid = 0, nInside = 0;
        bool bCapped = false;

        for (int n = 0; n < nCentres; n++)
        {
            (double dU, double dV, double dW) = R3(n + nSeedOffset);
            float fR = MathF.Sqrt((cell.RLoMm * cell.RLoMm) + ((float)dU * ((cell.RHiMm * cell.RHiMm) - (cell.RLoMm * cell.RLoMm))));
            float fPhi = 2f * MathF.PI * (float)dV;
            float fZ = cell.ZLoMm + ((float)dW * (cell.ZHiMm - cell.ZLoMm));
            (float fCos, float fSin) = (MathF.Cos(fPhi), MathF.Sin(fPhi));
            Vector3 vecCentre = new(fR * fCos, fR * fSin, fZ);
            Vector3 vecE1 = frame == Frame.Cylindrical ? new Vector3(fCos, fSin, 0f) : Vector3.UnitX;
            Vector3 vecE2 = frame == Frame.Cylindrical ? new Vector3(-fSin, fCos, 0f) : Vector3.UnitY;

            float fProbeHere = bCapProbeAtAxis ? MathF.Min(fProbeMm, fR) : fProbeMm;
            if (fProbeHere < fProbeMm) bCapped = true;
            int nSteps = Math.Max(2, (int)MathF.Round(fProbeHere / fStepMm));
            float fHalf = 0.5f * nSteps * fStepMm;

            for (int d = 0; d < aDirs.Length; d++)
            {
                Vector3 vecDir = (aDirs[d].X * vecE1) + (aDirs[d].Y * vecE2) + (aDirs[d].Z * Vector3.UnitZ);
                bool bHavePrev = false, bPrevSolid = false;
                for (int s = 0; s < nSteps; s++)
                {
                    Vector3 vecAt = vecCentre + (vecDir * (((s + 0.5f) * fStepMm) - fHalf));
                    if (!fnInBody(vecAt)) { bHavePrev = false; continue; }
                    bool bSolid = field.fSignedDistance(vecAt) < 0f;
                    nInside++;
                    if (bSolid) nSolid++;
                    // Length is counted per PAIR of consecutive inside samples — exactly the length over which a
                    // crossing could have been seen, so an outside gap costs neither a crossing nor a length.
                    if (bHavePrev)
                    {
                        aPairs[d]++;
                        if (bSolid != bPrevSolid) aCross[d]++;
                    }
                    bHavePrev = true;
                    bPrevSolid = bSolid;
                }
            }
        }

        var aPl2 = new double[aDirs.Length];
        long nCross = 0;
        double dProbed = 0.0, dPlSum = 0.0;
        for (int d = 0; d < aDirs.Length; d++)
        {
            double dLen = aPairs[d] * (double)fStepMm;
            if (dLen <= 0.0)
                throw new InvalidOperationException($"direction {d} probed nothing inside the body — the cell lies outside it");
            double dPl = aCross[d] / dLen;
            dPlSum += dPl;
            aPl2[d] = dPl * dPl;
            nCross += aCross[d];
            dProbed += dLen;
        }

        double[,] aQ = FitQuadraticForm(aDirs, aPl2);
        (double[] aEig, Vector3[] aVec) = SymmetricEigen(aQ);
        double dMean = aPl2.Average(), dSq = 0.0;
        for (int d = 0; d < aDirs.Length; d++)
        {
            Vector3 v = aDirs[d];
            double dFit = (aQ[0, 0] * v.X * v.X) + (aQ[1, 1] * v.Y * v.Y) + (aQ[2, 2] * v.Z * v.Z)
                          + (2.0 * ((aQ[0, 1] * v.X * v.Y) + (aQ[0, 2] * v.X * v.Z) + (aQ[1, 2] * v.Y * v.Z)));
            dSq += (dFit - aPl2[d]) * (dFit - aPl2[d]);
        }

        return new Fabric(
            nInside > 0 ? (double)nSolid / nInside : 0.0,
            [.. aEig.Select(e => Math.Sqrt(Math.Max(e, 0.0)))],
            aVec,
            Math.Sqrt(dSq / aDirs.Length) / dMean,
            dPlSum / aDirs.Length,
            nCross,
            dProbed,
            bCapped);
    }

    // The period the shipped generator puts at radius r — `Zone1Anode.Gyroid`'s own map, read rather than re-derived by
    // each reader: linear core → rim for the graded field, the zone's period for `stepped` (boundary at the mid-radius).
    internal static float PeriodAtMm(AnchorCem cem, float fRMm)
    {
        float fRCore = Zone1Anode.InnerRadiusMm(cem), fRRim = cem.OuterDiameterMm / 2f;
        float fPRim = cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;
        if (cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase))
            return fRMm < (fRCore + fRRim) / 2f ? cem.GyroidPeriodMm : fPRim;
        return cem.GyroidPeriodMm + ((fPRim - cem.GyroidPeriodMm) * BlendAt(fRCore, fRRim, fRMm));
    }

    // The NOMINAL of a shell: the shipped lattice held at one radius — a constant-period field with the period and wall
    // level the part has at r, in its own topology (`stepped`: its zone's period on the sheet formulation it ships with).
    internal static IImplicit Nominal(AnchorCem cem, float fRMm)
    {
        float fRCore = Zone1Anode.InnerRadiusMm(cem), fRRim = cem.OuterDiameterMm / 2f;
        float fPeriod = PeriodAtMm(cem, fRMm);
        if (cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase))
            return new CartesianGyroid(fPeriod, cem.GyroidWallParam);
        float fWallRim = cem.GyroidWallParamRim ?? cem.GyroidWallParam;
        float fWall = cem.GyroidWallParam + ((fWallRim - cem.GyroidWallParam) * BlendAt(fRCore, fRRim, fRMm));
        return new GradedCartesianGyroid(fRCore, fRRim, fPeriod, fPeriod, fWall, fWall,
            cem.Topology.Equals("network", StringComparison.OrdinalIgnoreCase));
    }

    private static float BlendAt(float fRCore, float fRRim, float fRMm)
        => fRRim > fRCore ? Math.Clamp((fRMm - fRCore) / (fRRim - fRCore), 0f, 1f) : 0f;

    /// <summary>
    /// The radial shell edges of a reading: equal width, EXCEPT that a `stepped` SKU gets an edge ON its zone seam —
    /// a shell straddling the seam mixes two lattices, its nominal takes whichever period its mean radius falls in, and
    /// its stretches then read a seam artefact rather than a shape (adversary 2026-10-22).
    /// ⛔ The ONE home of the rule: the `cellshape` verb bins both the fabric and the print-floor column by it, and the
    /// cache pin re-derives it — a rule living only in the verb was invisible to every test.
    /// </summary>
    internal static float[] ShellEdges(AnchorCem cem, int nShells)
    {
        float fRCore = Zone1Anode.InnerRadiusMm(cem), fRRim = cem.OuterDiameterMm / 2f;
        var aEdge = new float[nShells + 1];
        for (int s = 0; s <= nShells; s++) aEdge[s] = fRCore + ((fRRim - fRCore) * s / nShells);
        if (cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase) && nShells >= 2)
        {
            float fSeam = (fRCore + fRRim) / 2f;
            int nNearest = 1;
            for (int s = 1; s < nShells; s++)
                if (MathF.Abs(aEdge[s] - fSeam) < MathF.Abs(aEdge[nNearest] - fSeam)) nNearest = s;
            aEdge[nNearest] = fSeam;
        }
        return aEdge;
    }

    /// <summary>The shell a radius falls in, by those edges (the last shell owns its outer edge).</summary>
    internal static int ShellOf(float[] aEdge, float fRMm)
    {
        for (int e = 1; e < aEdge.Length - 1; e++)
            if (fRMm < aEdge[e]) return e - 1;
        return aEdge.Length - 2;
    }

    /// <summary>
    /// Bins a sampled grid's SOLID voxels by (shell × height), counting how many of them a second, OPENED grid no longer
    /// holds — the print-floor column of `cellshape`, cell by cell. The grid convention is `Connectivity.SampleAnchor`'s:
    /// x and y run from −R, z from 0, each voxel read at its centre.
    /// ⛔ Here rather than inside the verb because the verb's own copy could not be tested at all: a z-bin shifted by one
    /// left every test green while moving every per-cell number (adversary 2026-10-22).
    /// </summary>
    internal static (long[,] Solid, long[,] Removed) BinSolidByCell(
        in Connectivity.Grid grid, in Connectivity.Grid gridOpened,
        float[] aShellEdge, int nZBins, float fZStepMm, float fRRimMm)
    {
        int nShells = aShellEdge.Length - 1;
        var aSolid = new long[nShells, nZBins];
        var aRemoved = new long[nShells, nZBins];
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
                for (int k = 0; k < grid.Nz; k++)
                {
                    int idx = grid.Index(i, j, k);
                    if (grid.Cells[idx] != Phase.Solid) continue;
                    float fX = -fRRimMm + ((i + 0.5f) * grid.StepMm), fY = -fRRimMm + ((j + 0.5f) * grid.StepMm);
                    float fZ = (k + 0.5f) * grid.StepMm;
                    int s = ShellOf(aShellEdge, MathF.Sqrt((fX * fX) + (fY * fY)));
                    int b = Math.Clamp((int)(fZ / fZStepMm), 0, nZBins - 1);
                    aSolid[s, b]++;
                    if (gridOpened.Cells[idx] != Phase.Solid) aRemoved[s, b]++;
                }
        return (aSolid, aRemoved);
    }

    // The first-order phase map of `GradedCartesianGyroid` at (r, z) in the local frame (r̂, φ̂, ẑ), rows = ∂θ/∂(r, φ, z)
    // components — the matrix in the header. z is measured from the FIELD's origin, the one its phase grows from.
    // Inside the graded annulus only: past the rim (or inside a core) the period clamps and k′ = 0.
    internal static double[,] GradedJacobian(
        float fRCoreMm, float fRRimMm, float fPeriodCoreMm, float fPeriodRimMm, double dR, double dZ)
    {
        bool bGraded = fRRimMm > fRCoreMm && dR > fRCoreMm && dR < fRRimMm;
        double dT = fRRimMm > fRCoreMm ? Math.Clamp((dR - fRCoreMm) / (fRRimMm - fRCoreMm), 0.0, 1.0) : 0.0;
        double dP = fPeriodCoreMm + ((fPeriodRimMm - fPeriodCoreMm) * dT);
        double dPPrime = bGraded ? (fPeriodRimMm - fPeriodCoreMm) / (double)(fRRimMm - fRCoreMm) : 0.0;
        double dK = 2.0 * Math.PI / dP;
        double dKPrime = -2.0 * Math.PI * dPPrime / (dP * dP);
        return new double[,]
        {
            { dK + (dR * dKPrime), 0.0, 0.0 },
            { 0.0, dK, 0.0 },
            { dZ * dKPrime, 0.0, dK },
        };
    }

    // Principal STRETCHES of a cell under the phase map J, relative to a nominal wavenumber: λ_i = k_nominal/√eig(JᵀJ),
    // ASCENDING (the most compressed axis first). The measured counterpart is MeanPl(nominal)/P_L,i.
    internal static double[] PredictedStretches(double[,] aJ, double dKNominal)
    {
        var aJtJ = new double[3, 3];
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++)
                for (int m = 0; m < 3; m++)
                    aJtJ[i, j] += aJ[m, i] * aJ[m, j];
        (double[] aEig, _) = SymmetricEigen(aJtJ);
        return [.. aEig.Select(e => dKNominal / Math.Sqrt(e))];
    }

    // A field translated along its axis: f(x, y, z) = inner(x, y, z − shift). For the graded gyroid only θz feels it —
    // θx and θy do not depend on z — so this IS the «z origin in the middle of the part» variant of HW.33, exactly.
    internal sealed class AxiallyShiftedField(IImplicit oInner, float fShiftMm) : IImplicit
    {
        public float fSignedDistance(in Vector3 vecPt) => oInner.fSignedDistance(vecPt - new Vector3(0f, 0f, fShiftMm));
    }

    /// <summary>
    /// The phase map of <see cref="AxiallyShiftedField"/> over a graded gyroid: the SAME map read at z − shift, because
    /// only θz depends on z. ⛔ Lives beside the field: as a lambda in the verb, a wrong sign was invisible to every
    /// test (adversary, 2026-10-22).
    /// </summary>
    internal static double[,] ShiftedJacobian(AnchorCem cem, double dR, double dZ, double dShiftMm)
        => GradedJacobian(Zone1Anode.InnerRadiusMm(cem), cem.OuterDiameterMm / 2f, cem.GyroidPeriodMm,
            cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm, dR, dZ - dShiftMm);

    // The «grade the phase only in the plane» variant of HW.33: θx = k(r)·x and θy = k(r)·y as the shipped generator,
    // θz = k_ref·z with ONE wavenumber — so no z·k′ term, at the price of an axial period that is P_ref at every radius.
    // ⛔ An EXPERIMENT for the measurement, not a product generator: the part's geometry is `Zone1Anode.Gyroid`, and
    //    changing it is the founder's verdict (00_07 HW.33), not a side effect of having this class.
    internal sealed class InPlaneGradedGyroid(
        float fRCoreMm, float fRRimMm, float fPeriodCoreMm, float fPeriodRimMm,
        float fWallCore, float fWallRim, bool bNetwork, float fPeriodAxialMm) : IImplicit
    {
        private readonly float _fKAxial = 2f * MathF.PI / fPeriodAxialMm;

        public float fSignedDistance(in Vector3 vecPt)
        {
            float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y));
            float fT = fRRimMm > fRCoreMm ? Math.Clamp((fR - fRCoreMm) / (fRRimMm - fRCoreMm), 0f, 1f) : 0f;
            float fPeriod = fPeriodCoreMm + ((fPeriodRimMm - fPeriodCoreMm) * fT);
            float fWall = fWallCore + ((fWallRim - fWallCore) * fT);
            float fFreq = 2f * MathF.PI / fPeriod;
            float fX = fFreq * vecPt.X, fY = fFreq * vecPt.Y, fZ = _fKAxial * vecPt.Z;
            double dEq = (Math.Sin(fX) * Math.Cos(fY)) + (Math.Sin(fY) * Math.Cos(fZ)) + (Math.Sin(fZ) * Math.Cos(fX));
            return bNetwork
                ? (float)(dEq - (0.5f * (fWall - 1f)))
                : (float)(Math.Abs(dEq) - (0.5f * fWall));
        }
    }

    /// <summary>
    /// The phase map of <see cref="InPlaneGradedGyroid"/>: the graded map with the axial row replaced by ONE wavenumber,
    /// so the z·k′ entry is gone and the axial period is <paramref name="dPeriodAxialMm"/> at every radius. ⛔ Beside the
    /// field for the same reason as <see cref="ShiftedJacobian"/>.
    /// </summary>
    internal static double[,] InPlaneJacobian(AnchorCem cem, double dR, double dPeriodAxialMm)
    {
        double[,] aJ = GradedJacobian(Zone1Anode.InnerRadiusMm(cem), cem.OuterDiameterMm / 2f, cem.GyroidPeriodMm,
            cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm, dR, 0.0);
        aJ[2, 0] = 0.0;
        aJ[2, 2] = 2.0 * Math.PI / dPeriodAxialMm;
        return aJ;
    }

    // ── numerics ───────────────────────────────────────────────────────────────────────────────────────────────────

    // Fibonacci points on the upper hemisphere — near-uniform, deterministic.
    internal static Vector3[] Hemisphere(int n)
    {
        var a = new Vector3[n];
        double dGolden = Math.PI * (3.0 - Math.Sqrt(5.0));
        for (int i = 0; i < n; i++)
        {
            double dZ = (i + 0.5) / n;
            double dRho = Math.Sqrt(1.0 - (dZ * dZ));
            double dPhi = i * dGolden;
            a[i] = new Vector3((float)(dRho * Math.Cos(dPhi)), (float)(dRho * Math.Sin(dPhi)), (float)dZ);
        }
        return a;
    }

    // The R3 low-discrepancy sequence (Roberts): deterministic, so a re-run reproduces a committed cache sample for sample.
    private static (double, double, double) R3(int n)
    {
        const double dG = 1.2207440846057594; // the plastic number's 3-D analogue: x⁴ = x + 1
        double dA1 = 1.0 / dG, dA2 = 1.0 / (dG * dG), dA3 = 1.0 / (dG * dG * dG);
        return (Frac(0.5 + (n * dA1)), Frac(0.5 + (n * dA2)), Frac(0.5 + (n * dA3)));
    }

    private static double Frac(double d) => d - Math.Floor(d);

    // Least-squares symmetric Q from y_d = dᵀQd: six unknowns (Qxx, Qyy, Qzz, Qxy, Qxz, Qyz), normal equations.
    private static double[,] FitQuadraticForm(Vector3[] aDirs, double[] aY)
    {
        var aAtA = new double[6, 6];
        var aAtY = new double[6];
        foreach ((Vector3 v, double dY) in aDirs.Zip(aY))
        {
            double[] aRow = [v.X * v.X, v.Y * v.Y, v.Z * v.Z, 2.0 * v.X * v.Y, 2.0 * v.X * v.Z, 2.0 * v.Y * v.Z];
            for (int i = 0; i < 6; i++)
            {
                aAtY[i] += aRow[i] * dY;
                for (int j = 0; j < 6; j++) aAtA[i, j] += aRow[i] * aRow[j];
            }
        }
        double[] q = Solve(aAtA, aAtY);
        return new double[,] { { q[0], q[3], q[4] }, { q[3], q[1], q[5] }, { q[4], q[5], q[2] } };
    }

    // Gaussian elimination with partial pivoting — a 6×6, well conditioned on a hemisphere of directions.
    private static double[] Solve(double[,] aA, double[] aB)
    {
        int n = aB.Length;
        var a = (double[,])aA.Clone();
        var b = (double[])aB.Clone();
        for (int c = 0; c < n; c++)
        {
            int p = c;
            for (int r = c + 1; r < n; r++) if (Math.Abs(a[r, c]) > Math.Abs(a[p, c])) p = r;
            if (Math.Abs(a[p, c]) < 1e-14) throw new InvalidOperationException("singular fabric fit — directions do not span the quadratic forms");
            if (p != c)
            {
                for (int k = 0; k < n; k++) (a[c, k], a[p, k]) = (a[p, k], a[c, k]);
                (b[c], b[p]) = (b[p], b[c]);
            }
            for (int r = c + 1; r < n; r++)
            {
                double f = a[r, c] / a[c, c];
                for (int k = c; k < n; k++) a[r, k] -= f * a[c, k];
                b[r] -= f * b[c];
            }
        }
        var x = new double[n];
        for (int r = n - 1; r >= 0; r--)
        {
            double s = b[r];
            for (int k = r + 1; k < n; k++) s -= a[r, k] * x[k];
            x[r] = s / a[r, r];
        }
        return x;
    }

    // Cyclic Jacobi for a symmetric 3×3: eigenvalues DESCENDING with their unit eigenvectors.
    internal static (double[] Values, Vector3[] Vectors) SymmetricEigen(double[,] aM)
    {
        var a = (double[,])aM.Clone();
        var v = new double[,] { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
        for (int sweep = 0; sweep < 64; sweep++)
        {
            double dOff = Math.Abs(a[0, 1]) + Math.Abs(a[0, 2]) + Math.Abs(a[1, 2]);
            if (dOff < 1e-15 * (Math.Abs(a[0, 0]) + Math.Abs(a[1, 1]) + Math.Abs(a[2, 2]) + 1e-300)) break;
            for (int p = 0; p < 2; p++)
                for (int q = p + 1; q < 3; q++)
                {
                    if (Math.Abs(a[p, q]) < 1e-300) continue;
                    double dTheta = (a[q, q] - a[p, p]) / (2.0 * a[p, q]);
                    double t = Math.Sign(dTheta) / (Math.Abs(dTheta) + Math.Sqrt((dTheta * dTheta) + 1.0));
                    if (dTheta == 0.0) t = 1.0;
                    double c = 1.0 / Math.Sqrt((t * t) + 1.0), s = t * c;
                    for (int k = 0; k < 3; k++)
                    {
                        double dKp = a[k, p], dKq = a[k, q];
                        a[k, p] = (c * dKp) - (s * dKq);
                        a[k, q] = (s * dKp) + (c * dKq);
                    }
                    for (int k = 0; k < 3; k++)
                    {
                        double dPk = a[p, k], dQk = a[q, k];
                        a[p, k] = (c * dPk) - (s * dQk);
                        a[q, k] = (s * dPk) + (c * dQk);
                    }
                    for (int k = 0; k < 3; k++)
                    {
                        double dKp = v[k, p], dKq = v[k, q];
                        v[k, p] = (c * dKp) - (s * dKq);
                        v[k, q] = (s * dKp) + (c * dKq);
                    }
                }
        }
        int[] aOrder = [.. Enumerable.Range(0, 3).OrderByDescending(i => a[i, i])];
        return ([.. aOrder.Select(i => a[i, i])],
                [.. aOrder.Select(i => Vector3.Normalize(new Vector3((float)v[0, i], (float)v[1, i], (float)v[2, i])))]);
    }
}
