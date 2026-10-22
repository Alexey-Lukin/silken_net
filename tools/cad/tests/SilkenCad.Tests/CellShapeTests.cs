// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using System.Text.Json;
using PicoGK;

namespace SilkenCad.Tests;

// The line-intercept fabric (CellShape.cs, 00_07 HW.33). Pure-managed — the instrument reads the field's sign along probe
// lines, no PicoGK runtime.
// 🔑 Tolerances are the instrument's MEASURED floor, and the floor is SAMPLING, not the lattice's cubic anisotropy
//    (re-attributed 2026-10-22 after an adversary rebuilt the instrument in numpy): the exact shear pin below reads a
//    single stretch up to ~8 % off at 400 centres, ~5 % at the caches' 1500, and within ~1.3 % at 6000 or on an 8 mm
//    probe, while the cubic term itself leaks ≤ ~1.5 % into the second-order fit. These tests run at 400 centres to stay
//    fast, so they carry the widest floor of any reading in the tree — never quote a test's tolerance as the method's.
public class CellShapeTests
{
    private const int Centres = 400;
    private static readonly Func<Vector3, bool> Everywhere = static _ => true;

    // The shipped pine geometry (cem/anchor_zone1.pine.json) inline, so a manifest edit cannot quietly move the physics
    // under this test — the committed cache, not this test, describes the shipped SKUs.
    private static AnchorCem PineLike(float fPeriodRimMm = 2.0f, float? fWallRim = null, float fPeriodMm = 2.5f, float fWall = 0.1f) => new()
    {
        OuterDiameterMm = 11f, LengthMm = 40f, GyroidPeriodMm = fPeriodMm, GyroidPeriodRimMm = fPeriodRimMm,
        GyroidWallParam = fWall, GyroidWallParamRim = fWallRim, Topology = "network",
    };

    // The rim shell of the 11 mm part, from two-thirds of the radius out.
    private static readonly (float Lo, float Hi) RimShell = (11f / 3f, 5.5f);

    // A constant lattice under an explicit linear map of its argument: f(x) = inner(A·x), here A = I + γ·ẑ⊗x̂.
    private sealed class ShearedField(IImplicit oInner, float fGamma) : IImplicit
    {
        public float fSignedDistance(in Vector3 vecPt)
            => oInner.fSignedDistance(new Vector3(vecPt.X, vecPt.Y, vecPt.Z + (fGamma * vecPt.X)));
    }

    // IDENTITY CONTROL — an instrument that invents distortion would read it everywhere: a constant-period lattice must
    // read isotropic in both frames, low and high on the part.
    [Theory]
    [InlineData(0f, 5f, false)]
    [InlineData(35f, 40f, false)]
    [InlineData(35f, 40f, true)]
    public void A_Constant_Period_Lattice_Reads_Isotropic(float fZLo, float fZHi, bool bCartesian)
    {
        CellShape.Frame frame = bCartesian ? CellShape.Frame.Cartesian : CellShape.Frame.Cylindrical;
        AnchorCem cem = PineLike(fPeriodRimMm: 2.0f, fPeriodMm: 2.0f);
        CellShape.Fabric fab = CellShape.Measure(Zone1Anode.Gyroid(cem), new CellShape.Cell(fZLo, fZHi, RimShell.Lo, RimShell.Hi),
            Zone1Anode.Body(cem), fProbeMm: 2.0f, fStepMm: 0.04f, Centres, frame);

        Assert.True(fab.DegreeOfAnisotropy < 1.10, $"constant lattice read DA {fab.DegreeOfAnisotropy:F3} at z {fZLo}–{fZHi} ({frame})");
    }

    // ANALYTIC PIN — an exact answer, not a regression: a constant lattice under the simple shear A = I + γ·ẑ⊗x̂ is that
    // lattice mapped by A⁻¹, so its principal stretches are the reciprocal singular values of A — for γ = 1 the golden
    // ratio and its inverse, 0.618 · 1 · 1.618, and DA = φ² = 2.618. One number checks the crossing count, the quadratic
    // fit, the eigen-solver and the stretch convention together.
    // ⚠️ 10 %, because at 400 centres the sampling floor reaches ~8 % on a single stretch (header; measured 0.619 · 1.077 ·
    //    1.533 against the exact triple, the middle axis worst). Every error this pin exists for — an inverted stretch, a
    //    swapped order, a dropped factor of two — lands far outside it. ⛔ Do NOT attribute that 8 % to the gyroid's cubic
    //    anisotropy: it converges away with more centres, and the cubic term runs the other way (cube axes read ABOVE the
    //    directional mean).
    [Fact]
    public void An_Affinely_Sheared_Lattice_Reads_The_Exact_Stretches_Of_Its_Map()
    {
        var oInner = new GradedCartesianGyroid(0f, 5.5f, 2.0f, 2.0f, 0.1f, 0.1f, bNetwork: true, fPeriodAxialMm: 2.0f);
        var cell = new CellShape.Cell(10f, 15f, 0f, 4f);
        CellShape.Fabric nominal = CellShape.Measure(oInner, cell, Everywhere, 2.0f, 0.02f, Centres, CellShape.Frame.Cartesian);
        CellShape.Fabric sheared = CellShape.Measure(new ShearedField(oInner, 1f), cell, Everywhere, 2.0f, 0.02f, Centres, CellShape.Frame.Cartesian);

        double dPhi = (1.0 + Math.Sqrt(5.0)) / 2.0;
        double[] aExpected = [1.0 / dPhi, 1.0, dPhi];
        double[] aMeasured = sheared.StretchesAgainst(nominal);
        string strAll = $"measured [{string.Join(", ", aMeasured.Select(d => d.ToString("F3")))}] · nominal DA {nominal.DegreeOfAnisotropy:F3} · sheared DA {sheared.DegreeOfAnisotropy:F3}";
        for (int i = 0; i < 3; i++)
            Assert.True(Math.Abs(aMeasured[i] - aExpected[i]) / aExpected[i] < 0.10,
                $"stretch {i}: measured {aMeasured[i]:F3}, exact {aExpected[i]:F3} — {strAll}");
        Assert.True(Math.Abs(sheared.DegreeOfAnisotropy - (dPhi * dPhi)) / (dPhi * dPhi) < 0.10,
            $"DA measured {sheared.DegreeOfAnisotropy:F3}, exact {dPhi * dPhi:F3} — {strAll}");
        // The convention's own identity: a volume-keeping map keeps ∏λ = 1 (simple shear has det = 1).
        double dProduct = aMeasured[0] * aMeasured[1] * aMeasured[2];
        Assert.True(Math.Abs(dProduct - 1.0) < 0.10, $"∏λ {dProduct:F3} — a unimodular map must keep it at 1; {strAll}");
    }

    // THE CLAIM OF HW.33 — the PRE-VERDICT field's cell SHEARS with height while its porosity does not: at the top of the
    // rim shell the most compressed axis is less than half its nominal, at the bottom it is the in-plane term alone, both
    // within this test's floor of the first-order phase map (CellShape.GradedJacobian), and the porosity of the two cells
    // agrees. It is the instrument's sheared reference since the verdict moved the product off it (next tests).
    [Fact]
    public void A_Period_Graded_Lattice_Shears_With_Height_At_Constant_Porosity_As_Its_Phase_Map_Predicts()
    {
        AnchorCem cem = PineLike();
        IImplicit oField = CellShape.PreVerdictGyroid(cem);
        var cellBottom = new CellShape.Cell(0f, 5f, RimShell.Lo, RimShell.Hi);
        var cellTop = new CellShape.Cell(35f, 40f, RimShell.Lo, RimShell.Hi);
        float fRMean = cellTop.RMeanMm;
        float fPMean = CellShape.PeriodAtMm(cem, fRMean);

        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);
        CellShape.Fabric nominal = CellShape.Measure(CellShape.Nominal(cem, fRMean), cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric bottom = CellShape.Measure(oField, cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric top = CellShape.Measure(oField, cellTop, fnBody, fPMean, 0.02f, Centres);

        double dK = 2.0 * Math.PI / fPMean;
        double dPredBottom = CellShape.PredictedStretches(CellShape.ShiftedJacobian(cem, fRMean, cellBottom.ZMidMm, 0.0), dK)[0];
        double dPredTop = CellShape.PredictedStretches(CellShape.ShiftedJacobian(cem, fRMean, cellTop.ZMidMm, 0.0), dK)[0];
        double dBottom = bottom.StretchesAgainst(nominal)[0], dTop = top.StretchesAgainst(nominal)[0];

        Assert.True(dTop < 0.5, $"top-rim compressed stretch {dTop:F3} — the shear the phase map predicts ({dPredTop:F3}) is gone");
        Assert.True(Math.Abs(dTop - dPredTop) / dPredTop < 0.08, $"top: measured {dTop:F3}, phase map {dPredTop:F3}");
        Assert.True(Math.Abs(dBottom - dPredBottom) / dPredBottom < 0.08, $"bottom: measured {dBottom:F3}, phase map {dPredBottom:F3}");
        Assert.True(top.DegreeOfAnisotropy > 3.0 && bottom.DegreeOfAnisotropy < 1.5,
            $"DA top {top.DegreeOfAnisotropy:F2} (> 3 expected), bottom {bottom.DegreeOfAnisotropy:F2} (< 1.5 expected)");
        Assert.True(Math.Abs(top.SolidFraction - bottom.SolidFraction) < 0.03,
            $"porosity moved with height: top {1 - top.SolidFraction:P1}, bottom {1 - bottom.SolidFraction:P1}");
        // And the thing porosity hides but the probe lines give for free: the surface per volume rises with the shear.
        Assert.True(top.SpecificSurfacePerMm > 1.15 * bottom.SpecificSurfacePerMm,
            $"S_V top {top.SpecificSurfacePerMm:F3} vs bottom {bottom.SpecificSurfacePerMm:F3} — the shear must inflate it");
    }

    // 🔴 OPTION (б) of the HW.33 verdict — shifting the field's z origin to mid-part: the SAME map read at z − L/2, so the
    //    term halves and becomes SYMMETRIC — equal at the top and at the TREE-SIDE TIP (z = 0, the end that goes into the
    //    wood first). ⛔ Without this test, moving the shift's sign or its magnitude reddened nothing (adversary mutation
    //    M8 stayed green), and the verdict leg quotes both halves of this reading.
    [Fact]
    public void Shifting_The_Z_Origin_To_Mid_Part_Halves_The_Term_And_Mirrors_It_Onto_The_Tip()
    {
        AnchorCem cem = PineLike();
        IImplicit oShifted = new CellShape.AxiallyShiftedField(CellShape.PreVerdictGyroid(cem), cem.LengthMm / 2f);
        var cellBottom = new CellShape.Cell(0f, 5f, RimShell.Lo, RimShell.Hi);
        var cellTop = new CellShape.Cell(35f, 40f, RimShell.Lo, RimShell.Hi);
        float fRMean = cellTop.RMeanMm, fPMean = CellShape.PeriodAtMm(cem, fRMean);
        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);

        CellShape.Fabric nominal = CellShape.Measure(CellShape.Nominal(cem, fRMean), cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric top = CellShape.Measure(oShifted, cellTop, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric tip = CellShape.Measure(oShifted, cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric preVerdictTop = CellShape.Measure(CellShape.PreVerdictGyroid(cem), cellTop, fnBody, fPMean, 0.02f, Centres);

        double dTop = top.StretchesAgainst(nominal)[0], dTip = tip.StretchesAgainst(nominal)[0];
        double dK = 2.0 * Math.PI / fPMean;
        double dPredTop = CellShape.PredictedStretches(CellShape.ShiftedJacobian(cem, fRMean, cellTop.ZMidMm, cem.LengthMm / 2f), dK)[0];

        Assert.True(Math.Abs(dTop - dPredTop) / dPredTop < 0.08, $"shifted top: measured {dTop:F3}, its own phase map {dPredTop:F3}");
        Assert.True(Math.Abs(dTop - dTip) < 0.03, $"the shift must be SYMMETRIC: top {dTop:F3} vs tree-side tip {dTip:F3}");
        Assert.True(dTop > 1.25 * preVerdictTop.StretchesAgainst(nominal)[0],
            $"shifted top {dTop:F3} is no gentler than the pre-verdict field {preVerdictTop.StretchesAgainst(nominal)[0]:F3}");
        Assert.True(top.DegreeOfAnisotropy < 2.5 && top.DegreeOfAnisotropy > 1.5,
            $"shifted top DA {top.DegreeOfAnisotropy:F2} — expected the halved term, ~1.8–2.1 on this geometry");
    }

    // 🔴 OPTION (в) — grading the phase only IN PLANE, with ONE axial wavenumber: the z·k′ entry is gone, so the reading
    //    must be FLAT with height and match `InPlaneJacobian`. ⛔ Two adversary mutations stayed green without this: one
    //    made the field identical to as-built (M10), the other gave its Jacobian the wrong axial period (M7).
    [Fact]
    public void Grading_The_Phase_Only_In_Plane_Removes_The_Height_Term()
    {
        AnchorCem cem = PineLike();
        float fRMean = new CellShape.Cell(0f, 1f, RimShell.Lo, RimShell.Hi).RMeanMm;
        float fPAxial = 2.0f;  // the rim period — the recommendation's choice; the test only needs ONE axial period
        IImplicit oInPlane = new CellShape.InPlaneGradedGyroid(0f, 5.5f, 2.5f, 2.0f, 0.1f, 0.1f, bNetwork: true, fPAxial);
        var cellBottom = new CellShape.Cell(0f, 5f, RimShell.Lo, RimShell.Hi);
        var cellTop = new CellShape.Cell(35f, 40f, RimShell.Lo, RimShell.Hi);
        float fPMean = CellShape.PeriodAtMm(cem, fRMean);
        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);

        CellShape.Fabric nominal = CellShape.Measure(CellShape.Nominal(cem, fRMean), cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric bottom = CellShape.Measure(oInPlane, cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric top = CellShape.Measure(oInPlane, cellTop, fnBody, fPMean, 0.02f, Centres);
        double dBottom = bottom.StretchesAgainst(nominal)[0], dTop = top.StretchesAgainst(nominal)[0];
        double dPred = CellShape.PredictedStretches(CellShape.InPlaneJacobian(cem, fRMean, fPAxial), 2.0 * Math.PI / fPMean)[0];

        Assert.True(Math.Abs(dTop - dBottom) < 0.05, $"in-plane-only must be FLAT with height: bottom {dBottom:F3}, top {dTop:F3}");
        Assert.True(top.DegreeOfAnisotropy < 1.5, $"in-plane-only top DA {top.DegreeOfAnisotropy:F2} — the axial term is still there");
        Assert.True(Math.Abs(dTop - dPred) / dPred < 0.08, $"in-plane-only top: measured {dTop:F3}, its own phase map {dPred:F3}");
        // What NO option removes: the in-plane radial term itself, ε = r·|P′|/P ≈ 0.2 at the rim.
        Assert.True(dTop < 0.92, $"in-plane-only still carries the radial term — read {dTop:F3}, expected ≈ 1/(1+ε) ≈ 0.83");
    }

    // 🔴 THE VERDICT ITSELF (⚖️ founder 2026-10-22, 00_07 HW.33 option (в), canon 01_01 §5.5) — pinned by its FUNCTION in
    //    the part's own field, never by a parameter (picogk gotcha #15): the SHIPPED period-graded part is flat with height,
    //    reads its own in-plane map at the RIM's axial period, and is no longer the sheared field. ⛔ Reverting the rule in
    //    `Zone1Anode.Gyroid` (axial wavenumber back to k(r)) reds all three asserts; an axial period other than the rim's
    //    reds the map assert.
    [Fact]
    public void The_Shipped_Period_Graded_Part_Does_Not_Shear_With_Height()
    {
        AnchorCem cem = PineLike();
        IImplicit oField = Zone1Anode.Gyroid(cem);
        var cellBottom = new CellShape.Cell(0f, 5f, RimShell.Lo, RimShell.Hi);
        var cellTop = new CellShape.Cell(35f, 40f, RimShell.Lo, RimShell.Hi);
        float fRMean = cellTop.RMeanMm, fPMean = CellShape.PeriodAtMm(cem, fRMean);
        float fPRim = cem.GyroidPeriodRimMm;
        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);

        CellShape.Fabric nominal = CellShape.Measure(CellShape.Nominal(cem, fRMean), cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric bottom = CellShape.Measure(oField, cellBottom, fnBody, fPMean, 0.02f, Centres);
        CellShape.Fabric top = CellShape.Measure(oField, cellTop, fnBody, fPMean, 0.02f, Centres);
        double dBottom = bottom.StretchesAgainst(nominal)[0], dTop = top.StretchesAgainst(nominal)[0];
        double dPred = CellShape.PredictedStretches(CellShape.InPlaneJacobian(cem, fRMean, fPRim), 2.0 * Math.PI / fPMean)[0];

        Assert.True(Math.Abs(dTop - dBottom) < 0.05, $"shipped part must be FLAT with height: bottom {dBottom:F3}, top {dTop:F3}");
        Assert.True(top.DegreeOfAnisotropy < 1.5, $"shipped top DA {top.DegreeOfAnisotropy:F2} — the axial shear is back");
        Assert.True(Math.Abs(dTop - dPred) / dPred < 0.08, $"shipped top: measured {dTop:F3}, the rim-axial map {dPred:F3}");
    }

    // 🔴 THE PHASE-LOCK GUARD (picogk gotcha #16's class, on this instrument): with ONE sample sequence for every cell,
    //    two cells of a CONSTANT-period lattice whose bins sit an integer number of periods apart sample the same phases
    //    point for point — the period-constant control's eight bins were four distinct samples until 2026-10-22. The knob
    //    that fixes it is `nSeedOffset`, and this pins both halves: same offset ⇒ identical, different offset ⇒ not.
    [Fact]
    public void Cells_An_Integer_Number_Of_Periods_Apart_Must_Not_Share_Sample_Phases()
    {
        AnchorCem cem = PineLike(fPeriodRimMm: 2.0f, fPeriodMm: 2.0f);
        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);
        var cellA = new CellShape.Cell(10f, 15f, RimShell.Lo, RimShell.Hi);
        var cellB = new CellShape.Cell(20f, 25f, RimShell.Lo, RimShell.Hi); // exactly 5 periods higher
        IImplicit oField = Zone1Anode.Gyroid(cem);

        CellShape.Fabric a = CellShape.Measure(oField, cellA, fnBody, 2.0f, 0.02f, Centres);
        CellShape.Fabric bSameSeed = CellShape.Measure(oField, cellB, fnBody, 2.0f, 0.02f, Centres);
        CellShape.Fabric bOwnSeed = CellShape.Measure(oField, cellB, fnBody, 2.0f, 0.02f, Centres, nSeedOffset: Centres);

        Assert.Equal(a.Crossings, bSameSeed.Crossings);   // the defect, demonstrated: one sequence ⇒ one sample
        Assert.NotEqual(a.Crossings, bOwnSeed.Crossings); // the fix: a per-cell offset ⇒ independent samples
    }

    // 🔴 THE PRINT-FLOOR BINNING, exercised directly on a hand-built grid — the column canon quotes as the
    //    thickness-sensitive reading. ⛔ A z-bin shifted by one moved every per-cell number and reddened nothing, because
    //    no test ran the verb's own copy (adversary mutation M9); the rule now lives in `CellShape.BinSolidByCell` and
    //    this grid places one solid voxel per cell, so a shifted or mis-shelled bin is immediate.
    [Fact]
    public void The_Print_Floor_Column_Bins_A_Voxel_By_Its_Own_Radius_And_Height()
    {
        const float fStep = 1.0f, fRRim = 5.5f, fZStep = 5f;
        const int nZBins = 8, nShells = 3;
        AnchorCem cem = PineLike();
        float[] aEdge = CellShape.ShellEdges(cem, nShells);   // 0 · 1.833 · 3.667 · 5.5
        int nx = (int)(2 * fRRim / fStep), nz = (int)(nZBins * fZStep / fStep);
        var aCells = new Phase[nx * nx * nz];
        var aOpened = new Phase[nx * nx * nz];
        int Index(int i, int j, int k) => ((i * nx) + j) * nz + k;
        // One solid voxel at (x ≈ r, y ≈ 0) for each shell, at a known height; the opened grid keeps only the first.
        (float R, float Z, int Shell, int Bin)[] aPlace =
        [
            (1.0f, 2.5f, 0, 0),    // core shell, bottom bin
            (2.5f, 22.5f, 1, 4),   // middle shell, middle bin
            (4.5f, 37.5f, 2, 7),   // outer shell, top bin
        ];
        foreach ((float fR, float fZ, _, _) in aPlace)
        {
            int i = (int)((fR + fRRim) / fStep), j = (int)fRRim, k = (int)(fZ / fStep);
            aCells[Index(i, j, k)] = Phase.Solid;
            aOpened[Index(i, j, k)] = Phase.Solid;
        }
        // Remove the FIRST one in the opened grid, so exactly one cell reports a removal.
        {
            int i = (int)((aPlace[0].R + fRRim) / fStep), j = (int)fRRim, k = (int)(aPlace[0].Z / fStep);
            aOpened[Index(i, j, k)] = Phase.Pore;
        }
        var grid = new Connectivity.Grid(aCells, nx, nx, nz, fStep);
        var opened = new Connectivity.Grid(aOpened, nx, nx, nz, fStep);

        (long[,] aSolid, long[,] aRemoved) = CellShape.BinSolidByCell(grid, opened, aEdge, nZBins, fZStep, fRRim);

        Assert.Equal(3, aSolid.Cast<long>().Sum());
        Assert.Equal(1, aRemoved.Cast<long>().Sum());
        foreach ((float fR, float fZ, int nShell, int nBin) in aPlace)
            Assert.True(aSolid[nShell, nBin] == 1,
                $"a voxel at r ≈ {fR}, z = {fZ} must land in shell {nShell}, bin {nBin} — "
                + $"that cell holds {aSolid[nShell, nBin]}, and the grid total is {aSolid.Cast<long>().Sum()}");
        Assert.Equal(1, aRemoved[aPlace[0].Shell, aPlace[0].Bin]);
    }

    // CONTROL with the same generator — a period-CONSTANT part has k′ = 0, so nothing shears, even under a porosity
    // gradient (the `graded_porosity` form: wall graded, period not): its top reads as isotropic as a constant lattice.
    [Fact]
    public void A_Period_Constant_Part_Does_Not_Shear_Even_With_A_Porosity_Gradient()
    {
        AnchorCem cem = PineLike(fPeriodRimMm: 2.0f, fWallRim: -0.46f, fPeriodMm: 2.0f, fWall: 0.52f);
        CellShape.Fabric top = CellShape.Measure(Zone1Anode.Gyroid(cem), new CellShape.Cell(35f, 40f, RimShell.Lo, RimShell.Hi),
            Zone1Anode.Body(cem), 2.0f, 0.02f, Centres);

        Assert.True(top.DegreeOfAnisotropy < 1.15, $"period-constant top read DA {top.DegreeOfAnisotropy:F3}");
    }

    // 🔴 THE CACHE PIN — canon quotes `cache/topology/cellshape.<name>.json` (01_01 §5.5), so an instrument changed without
    //    a re-run would leave every cache describing an instrument that no longer exists, and nothing would redden (the
    //    convergence pin's class, picogk gotcha #14). Re-measures, with the cache's OWN recorded settings and the verb's
    //    own seeds and probe cap, the row canon quotes — top bin, outer shell — for EVERY variant, and re-derives that
    //    variant's prediction from the Jacobian that lives beside its field. Also closes the per-cell sub-floor column:
    //    Σ(removed)/Σ(solid) over the cells must equal the whole-part figure, which `verify`'s golden carries too.
    //    ⚠️ 1e-3, not exact: the sampling is deterministic, but a last-ulp difference in a platform's sin/cos can flip a
    //    sample sitting on a boundary — one crossing in ~10⁴ moves a stretch by ~10⁻⁴.
    [Theory]
    [MemberData(nameof(AnchorTests.ShippedAnchorCems), MemberType = typeof(AnchorTests))]
    public void Every_Committed_Cellshape_Cache_Was_Measured_By_Todays_Instrument(string strFile)
    {
        AnchorCem cem = CemFixtures.Anchor(strFile);
        string strPath = Path.Combine(Directory.GetParent(CemFixtures.Dir())!.FullName, "cache", "topology", $"cellshape.{cem.Name}.json");
        Assert.True(File.Exists(strPath), $"{cem.Name}: no committed cellshape cache — run `cellshape cem/{strFile}` (00_07 HW.33)");
        using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(strPath));
        JsonElement root = doc.RootElement;
        float fStep = root.GetProperty("probe_step_mm").GetSingle();
        int nCentres = root.GetProperty("centres_per_cell").GetInt32();
        float? fAxialPeriod = root.GetProperty("in_plane_only_axial_period_mm").ValueKind == JsonValueKind.Null
            ? null : root.GetProperty("in_plane_only_axial_period_mm").GetSingle();
        Func<Vector3, bool> fnBody = Zone1Anode.Body(cem);
        float fRRim = cem.OuterDiameterMm / 2f, fRCore = Zone1Anode.InnerRadiusMm(cem);
        float fPRim = cem.GyroidPeriodRimMm > 0f ? cem.GyroidPeriodRimMm : cem.GyroidPeriodMm;

        JsonElement[] aVariants = [.. root.GetProperty("variants").EnumerateArray()];
        Assert.Equal("as_built", aVariants[0].GetProperty("variant").GetString());

        foreach (JsonElement variant in aVariants)
        {
            string strVariant = variant.GetProperty("variant").GetString()!;
            JsonElement[] aRows = [.. variant.GetProperty("rows").EnumerateArray()];
            int nShells = aRows.Max(r => r.GetProperty("shell").GetInt32()) + 1;
            int nBins = aRows.Count(r => r.GetProperty("shell").GetInt32() == 0);
            JsonElement[] aOuter = [.. aRows.Where(r => r.GetProperty("shell").GetInt32() == nShells - 1)
                .OrderBy(r => r.GetProperty("z_lo_mm").GetSingle())];
            static CellShape.Cell CellOf(JsonElement r) => new(r.GetProperty("z_lo_mm").GetSingle(), r.GetProperty("z_hi_mm").GetSingle(),
                r.GetProperty("r_lo_mm").GetSingle(), r.GetProperty("r_hi_mm").GetSingle());
            CellShape.Cell cellTop = CellOf(aOuter[^1]), cellBottom = CellOf(aOuter[0]);
            float fRMean = cellTop.RMeanMm, fProbe = CellShape.PeriodAtMm(cem, fRMean);
            int nShell = nShells - 1, nBin = nBins - 1;

            IImplicit oField = strVariant switch
            {
                "as_built" => Zone1Anode.Gyroid(cem),
                "pre_verdict" => CellShape.PreVerdictGyroid(cem),
                "z_origin_mid" => new CellShape.AxiallyShiftedField(CellShape.PreVerdictGyroid(cem), cem.LengthMm / 2f),
                "in_plane_only" => new CellShape.InPlaneGradedGyroid(fRCore, fRRim, cem.GyroidPeriodMm, fPRim,
                    cem.GyroidWallParam, cem.GyroidWallParamRim ?? cem.GyroidWallParam,
                    cem.Topology.Equals("network", StringComparison.OrdinalIgnoreCase), fAxialPeriod!.Value),
                _ => throw new InvalidOperationException($"{cem.Name}: cache carries an unknown variant `{strVariant}`"),
            };
            double[,]? aJ = strVariant switch
            {
                "as_built" => fPRim != cem.GyroidPeriodMm && !cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase)
                    ? CellShape.InPlaneJacobian(cem, fRMean, Zone1Anode.AxialPeriodMm(cem)) : null,
                "pre_verdict" => CellShape.ShiftedJacobian(cem, fRMean, cellTop.ZMidMm, 0.0),
                "z_origin_mid" => CellShape.ShiftedJacobian(cem, fRMean, cellTop.ZMidMm, cem.LengthMm / 2.0),
                "in_plane_only" => CellShape.InPlaneJacobian(cem, fRMean, fAxialPeriod!.Value),
                _ => null,
            };

            // Two rows, not one: the OUTER shell's top (what canon quotes) and the CORE shell's top — the only place the
            // axis probe cap bites, so without it a cap that stopped working reddened nothing.
            JsonElement[] aCore = [.. aRows.Where(r => r.GetProperty("shell").GetInt32() == 0)
                .OrderBy(r => r.GetProperty("z_lo_mm").GetSingle())];
            foreach ((int nS, int nB, JsonElement rowSaid) in new[]
                     { (nShell, nBin, aOuter[^1]), (0, nBins - 1, aCore[^1]) })
            {
                CellShape.Cell cell = CellOf(rowSaid);
                float fR = cell.RMeanMm, fProbeHere = CellShape.PeriodAtMm(cem, fR);
                CellShape.Cell cellRef = CellOf(aRows.First(r => r.GetProperty("shell").GetInt32() == nS
                    && r.GetProperty("z_lo_mm").GetSingle() == aOuter[0].GetProperty("z_lo_mm").GetSingle()));
                CellShape.Fabric nominal = CellShape.Measure(CellShape.Nominal(cem, fR), cellRef, fnBody, fProbeHere, fStep, nCentres,
                    nSeedOffset: (nS + 1) * nCentres, bCapProbeAtAxis: true);
                CellShape.Fabric now = CellShape.Measure(oField, cell, fnBody, fProbeHere, fStep, nCentres,
                    nSeedOffset: ((nS * nBins) + nB + nShells + 1) * nCentres, bCapProbeAtAxis: true);

                double[] aNow = now.StretchesAgainst(nominal);
                double[] aSaid = [.. rowSaid.GetProperty("stretch_measured").EnumerateArray().Select(e => e.GetDouble())];
                for (int i = 0; i < 3; i++)
                    Assert.True(Math.Abs(aNow[i] - aSaid[i]) <= 1e-3 * aSaid[i],
                        $"{cem.Name} [{strVariant}] shell {nS}: top stretch {i} committed {aSaid[i]:F5}, today's instrument "
                        + $"{aNow[i]:F5} — re-run `cellshape cem/{strFile}`");
                Assert.Equal(rowSaid.GetProperty("probe_capped_at_axis").GetBoolean(), now.ProbeCappedAtAxis);
            }

            JsonElement predicted = aOuter[^1].GetProperty("stretch_predicted");
            if (aJ is null)
                Assert.Equal(JsonValueKind.Null, predicted.ValueKind);
            else
            {
                double[] aPredNow = CellShape.PredictedStretches(aJ, 2.0 * Math.PI / fProbe);
                double[] aPredSaid = [.. predicted.EnumerateArray().Select(e => e.GetDouble())];
                for (int i = 0; i < 3; i++)
                    Assert.True(Math.Abs(aPredNow[i] - aPredSaid[i]) <= 1e-6 + (1e-3 * aPredSaid[i]),
                        $"{cem.Name} [{strVariant}]: predicted stretch {i} committed {aPredSaid[i]:F5}, today's map {aPredNow[i]:F5}");
            }

            // The per-cell sub-floor column against its own whole-part figure: Σremoved/Σsolid. Recomputed from the rows'
            // own fractions needs the cell solid counts, which the cache does not carry — so instead pin the two
            // statements the canon quotes: the whole-part number is the golden's, and no cell is below the whole part's
            // minimum or above its own reported worst.
            double dWhole = variant.GetProperty("sub_floor_solid_fraction_whole_part").GetDouble();
            double dWorst = variant.GetProperty("max_sub_floor_solid_fraction_by_cell").GetDouble();
            double[] aCellShares = [.. aRows.Select(r => r.GetProperty("sub_floor_solid_fraction").GetDouble())];
            Assert.True(Math.Abs(aCellShares.Max() - dWorst) < 1e-12,
                $"{cem.Name} [{strVariant}]: worst cell {dWorst:F6} is not the maximum of the rows ({aCellShares.Max():F6})");
            Assert.True(aCellShares.Min() <= dWhole + 1e-12 && dWhole <= aCellShares.Max() + 1e-12,
                $"{cem.Name} [{strVariant}]: whole-part {dWhole:F6} lies outside the cells' range {aCellShares.Min():F6}–{aCellShares.Max():F6}");

            // The SHELL EDGES, re-derived from the ONE rule (`CellShape.ShellEdges`) and checked against what the cache
            // says it used. ⛔ The cache is the frozen witness here: a changed edge rule moves every per-cell number into
            // a different shell, and without this comparison it reddened nothing (adversary mutation M14).
            float[] aEdge = CellShape.ShellEdges(cem, nShells);
            foreach (JsonElement row in aRows)
            {
                int s = row.GetProperty("shell").GetInt32();
                Assert.Equal(aEdge[s], row.GetProperty("r_lo_mm").GetSingle(), 4);
                Assert.Equal(aEdge[s + 1], row.GetProperty("r_hi_mm").GetSingle(), 4);
            }

            // The print-floor column's own WITNESS: the per-cell solid-voxel counts the verb binned. Three statements the
            // cache can be judged on without re-opening the grid (which costs seconds per SKU):
            //   · the counts partition the grid — Σ cells = the grid's solid total;
            //   · the whole-part share is their weighted mean, exactly (so it cannot be a figure from elsewhere);
            //   · within a shell the counts are nearly EQUAL across height — the lattice is uniform in z, so a bin that
            //     is empty or doubled is a mis-binned column (adversary mutation M9), not a property of the part.
            long nGridSolid = variant.GetProperty("sub_floor_grid_solid_voxels").GetInt64();
            long[] aCellSolid = [.. aRows.Select(r => r.GetProperty("sub_floor_cell_solid_voxels").GetInt64())];
            Assert.Equal(nGridSolid, aCellSolid.Sum());
            double dWeighted = aRows.Sum(r => r.GetProperty("sub_floor_solid_fraction").GetDouble()
                                              * r.GetProperty("sub_floor_cell_solid_voxels").GetInt64()) / nGridSolid;
            Assert.Equal(variant.GetProperty("sub_floor_solid_fraction_whole_part").GetDouble(), dWeighted, 9);
            for (int sh = 0; sh < nShells; sh++)
            {
                long[] aInShell = [.. aRows.Where(r => r.GetProperty("shell").GetInt32() == sh)
                    .Select(r => r.GetProperty("sub_floor_cell_solid_voxels").GetInt64())];
                double dMean = aInShell.Average();
                Assert.True(aInShell.Min() > 0.70 * dMean && aInShell.Max() < 1.30 * dMean,
                    $"{cem.Name} [{strVariant}] shell {sh}: height bins hold {aInShell.Min()}–{aInShell.Max()} solid voxels "
                    + $"around a mean of {dMean:F0} — the lattice is uniform in z, so this is a mis-binned column");
            }

            // 🔴 The per-cell sub-floor column is what the canon quotes as the THICKNESS-sensitive reading, and the claim
            //    has a SHAPE: on a period-graded part the as-built share grows with height in the outer shell (the shear
            //    thins the metal where it is strongest, 1.9–3.3× bottom to top), while the mid-origin and in-plane
            //    variants are FLAT or symmetric. Pinning the shape — and that no cell reports a zero — also catches a
            //    mis-binned column (adversary mutation M9), which the sums alone cannot see.
            //    ⚠️ NOT monotone bin by bin: on the SKUs whose shares are smallest (tropical, 0.16–0.42 %) the grid's own
            //    aliasing moves a bin by more than the trend does, so the pin is on the HALVES. The END bins also carry
            //    ~0.1 pp of end-face clipping — visible in the period-constant control, which rises at both ends.
            Assert.True(aCellShares.Min() > 0.0,
                $"{cem.Name} [{strVariant}]: a cell reports ZERO sub-floor metal — every cell of the part has lattice in it, "
                + "so a zero means the column was binned wrong, not that the cell is clean");
            double[] aOuterShares = [.. aOuter.Select(r => r.GetProperty("sub_floor_solid_fraction").GetDouble())];
            int nHalf = aOuterShares.Length / 2;
            double dLow = aOuterShares.Take(nHalf).Average(), dHigh = aOuterShares.Skip(nHalf).Average();
            if (fPRim != cem.GyroidPeriodMm && !cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase))
            {
                // ⚖️ HW.33 (в): the SHIPPED field is in-plane-graded, so it falls in the FLAT branch below; the growth
                //    with height belongs to the field shipped before the verdict.
                if (strVariant == "pre_verdict")
                {
                    Assert.True(aOuterShares[^1] > 1.5 * aOuterShares[0],
                        $"{cem.Name}: pre-verdict outer-shell sub-floor must grow with the shear — bottom {aOuterShares[0]:P2}, top {aOuterShares[^1]:P2}");
                    Assert.True(dHigh > 1.3 * dLow,
                        $"{cem.Name}: pre-verdict outer-shell sub-floor halves {dLow:P2} → {dHigh:P2} — the trend is gone");
                }
                else if (strVariant == "z_origin_mid")
                {
                    double dMid = aOuterShares[nHalf];
                    Assert.True(Math.Abs(aOuterShares[0] - aOuterShares[^1]) < 0.25 * aOuterShares[^1],
                        $"{cem.Name}: the mid-origin variant must be symmetric — tip {aOuterShares[0]:P2}, top {aOuterShares[^1]:P2}");
                    Assert.True(dMid < aOuterShares[0] && dMid < aOuterShares[^1],
                        $"{cem.Name}: the mid-origin variant's middle {dMid:P2} must be the gentlest, not its ends");
                }
                else
                {
                    Assert.True(Math.Abs(dHigh - dLow) < 0.15 * dLow,
                        $"{cem.Name} [{strVariant}]: an in-plane-graded field must be FLAT by height — halves {dLow:P2} → {dHigh:P2}");
                }
            }
        }

        // The as-built whole-part sub-floor IS `verify`'s golden metric — one home, two readers.
        string strGolden = Path.Combine(CemFixtures.Dir(), strFile.Replace(".json", ".golden.json"));
        if (File.Exists(strGolden))
        {
            using JsonDocument gold = JsonDocument.Parse(File.ReadAllText(strGolden));
            if (gold.RootElement.TryGetProperty("print_fidelity_sub_floor_solid_fraction", out JsonElement elem))
                Assert.Equal(elem.GetDouble(), aVariants[0].GetProperty("sub_floor_solid_fraction_whole_part").GetDouble(), 12);
        }
    }
}
