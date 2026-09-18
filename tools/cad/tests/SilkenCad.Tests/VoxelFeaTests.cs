// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;

namespace SilkenCad.Tests;

// Pins for the voxel-FE elasticity engine (VoxelFea.cs, 00_07 HW.51 / HW.33). Pure-managed like the
// rest of this suite — no PicoGK Library.Go, no display.
//
// 🔑 The shape of this file is deliberate: an FE solver is the kind of code that produces a
// confident number whatever it does, so every pin here is a case with a CLOSED-FORM answer, not a
// regression baseline. A baseline pins that the number stopped changing; these pin that it is right.
public class VoxelFeaTests
{
    // A cube of the given size, every cell solid — the calibration specimen.
    private static Connectivity.Grid SolidBox(int n, float fStepMm)
    {
        var aCells = new Phase[n * n * n];
        Array.Fill(aCells, Phase.Solid);
        return new Connectivity.Grid(aCells, n, n, n, fStepMm);
    }

    // 🔴 THE calibration. Frictionless platens on a fully solid specimen put it in uniform uniaxial
    // stress, so the apparent modulus must be the solid modulus EXACTLY — no discretisation error is
    // possible, because the exact solution is linear and trilinear elements reproduce it. That makes
    // this one number a simultaneous check of the element matrix, the assembly, the constrained-DOF
    // projection, the reaction sum and the nominal-area convention: break any of the five and it moves.
    // MUTATION: in HexElementStiffness change `dScale` to `1.0 / dSideMm` (drop the factor 2) ⇒ this
    // reds at 0.25 of E_solid, and so does every axial row the CLI prints.
    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    public void A_Solid_Specimen_Returns_The_Solid_Modulus_Exactly(int iAxis)
    {
        VoxelFea.FeaResult o = VoxelFea.ApparentAxialModulus(SolidBox(6, 0.25f), iAxis);
        Assert.True(o.Converged, $"CG did not converge on a solid box (residual {o.Residual:E2})");
        Assert.True(Math.Abs(o.StiffnessRatio - 1.0) < 1e-6,
            $"a fully solid specimen loaded along axis {iAxis} returned {o.StiffnessRatio:F9} of E_solid — " +
            "uniform uniaxial stress has no discretisation error, so this can only be the solver");
    }

    // The second closed form, and it is the one that proves the NOMINAL-AREA convention rather than
    // the element: a solid column of known section inside an otherwise empty envelope carries the
    // whole load at uniform stress, so the apparent modulus over the ENVELOPE area is exactly the
    // area fraction. If the code silently divided by the metal area instead, this would read 1.0.
    // MUTATION: make Build() count solid cells instead of inside cells for the nominal area ⇒ 1.0.
    [Fact]
    public void A_Solid_Column_Reads_Its_Own_Area_Fraction()
    {
        const int n = 8;
        var aCells = new Phase[n * n * n];
        var grid = new Connectivity.Grid(aCells, n, n, n, 0.25f);
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                for (int k = 0; k < n; k++)
                    aCells[grid.Index(i, j, k)] = i is >= 2 and < 6 && j is >= 2 and < 6
                        ? Phase.Solid : Phase.Pore; // 4×4 column of 8×8 ⇒ exactly 1/4 of the section

        VoxelFea.FeaResult o = VoxelFea.ApparentAxialModulus(grid, 2);
        Assert.True(o.Converged);
        Assert.True(Math.Abs(o.StiffnessRatio - 0.25) < 1e-6,
            $"a column filling a quarter of the section read {o.StiffnessRatio:F9}, not 0.25 — " +
            "apparent stress must be taken over the SPECIMEN's section, not the metal's");
    }

    // Bonded platens restrain the lateral contraction of the specimen ends, so a short solid block
    // must read STIFFER than E_solid. This is the only pin that proves ν reaches the element matrix
    // at all: at ν = 0 the two boundary conditions would give the same answer.
    // MUTATION: set SolidPoissonRatio to 0 ⇒ the bonded and frictionless numbers collapse together.
    [Fact]
    public void Bonded_Platens_Read_Stiffer_Than_Frictionless()
    {
        Connectivity.Grid grid = SolidBox(6, 0.25f);
        double dFree = VoxelFea.ApparentAxialModulus(grid, 2).StiffnessRatio;
        double dBonded = VoxelFea.ApparentAxialModulus(grid, 2, bBonded: true).StiffnessRatio;
        Assert.True(dBonded > dFree * 1.02,
            $"bonded platens read {dBonded:F4} against frictionless {dFree:F4} — lateral restraint on a " +
            "short specimen must stiffen it, so these two cannot agree unless ν never reached the matrix");
    }

    // A floating island has rigid-body modes; meshed, it makes the system singular and the solver
    // reports a confident number for a structure that is not one. It is excluded instead, and what
    // was excluded is REPORTED — the count is a finding about the geometry, never a silent repair.
    // MUTATION: mesh every solid cell instead of the largest body ⇒ CG stops converging here.
    [Fact]
    public void A_Floating_Island_Is_Dropped_And_Declared()
    {
        const int n = 8;
        var aCells = new Phase[n * n * n];
        var grid = new Connectivity.Grid(aCells, n, n, n, 0.25f);
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                for (int k = 0; k < n; k++)
                    aCells[grid.Index(i, j, k)] = i is >= 2 and < 6 && j is >= 2 and < 6
                        ? Phase.Solid : Phase.Pore;
        aCells[grid.Index(0, 0, 0)] = Phase.Solid; // one detached voxel, touching the column nowhere

        VoxelFea.FeaResult o = VoxelFea.ApparentAxialModulus(grid, 2);
        Assert.True(o.Converged, "a detached voxel must be excluded, not solved around");
        Assert.True(o.DiscardedIslandFraction > 0.0, "the excluded metal must be reported, not absorbed");
        Assert.True(Math.Abs(o.StiffnessRatio - 0.25) < 1e-6,
            $"the island changed the answer to {o.StiffnessRatio:F9} — it carries no load and must not");
    }

    // 🔴 This pin holds a REFUTATION, and what it refutes is the sentence that stood here first.
    // The fear driving the whole measurement was a SIZE EFFECT: a specimen only a few cells across
    // should be softer than the same lattice at continuum scale, and the shipped part spans just
    // 1.50–2.50 cells across its radial wall (01_01 §5.2 uncertainty (4)). Measured, that fear is
    // EMPTY for a network gyroid — one cell through eight agree within 0.2 %
    // (`cache/fea/size_effect_ladder.network.json`). A bicontinuous solid has no slender struts for a
    // free surface to cut; the cut face is solid, so the load paths survive.
    // ⚠️ And the first version of this test asserted the OPPOSITE and PASSED. At 8 steps/period a
    // one-cell cube reads ~0.065 against ~0.082 for two cells, which looks exactly like a size effect
    // and is DISCRETISATION: at one cell the same absolute voxel resolves the cut surfaces far worse,
    // and the error shrinks as the specimen grows. The verdict "the part is in the few-cell regime"
    // was true; the ground "therefore it is softer" was not. So the pin now holds BOTH halves — flat
    // where the grid is adequate, spuriously steep where it is not — because either half alone is the
    // trap the other one names.
    // MUTATION: make SampleLatticeCube ignore nStepsPerPeriod and use one fixed voxel ⇒ the coarse
    // half collapses onto the fine one and the second assert reds.
    [Fact]
    public void The_Size_Effect_Is_Absent_At_Adequate_Resolution_And_SPURIOUS_At_Coarse()
    {
        double Cube(int nCells, int nSteps) => VoxelFea.ApparentAxialModulus(
            VoxelFea.SampleLatticeCube(2.0f, 0.10f, bNetwork: true, nCells, nSteps), 2).StiffnessRatio;

        double dFineOne = Cube(1, 16), dFineTwo = Cube(2, 16);
        Assert.True(Math.Abs(dFineTwo - dFineOne) < 0.02 * dFineTwo,
            $"at an adequate grid one cell read {dFineOne:F4} and two cells {dFineTwo:F4} — a network " +
            "gyroid has no measurable size effect, so a gap here means the claim in 01_01 §5.2 moved");

        double dCoarseOne = Cube(1, 8), dCoarseTwo = Cube(2, 8);
        Assert.True(dCoarseTwo > dCoarseOne * 1.15,
            $"at a coarse grid one cell read {dCoarseOne:F4} and two cells {dCoarseTwo:F4} — the apparent " +
            "'size effect' must still appear here, because it is the DISCRETISATION artefact this pin exists to name");
    }

    // ⛔ The pin that stood here — «the monolithic rod enters only through the override» — went out with the
    // override itself on 2026-09-18: the anode is printed WITHOUT a core (welded wire, ⚖️ 2026-09-10), so the
    // configuration it guarded does not exist and a pin over it would be green on an empty subject.
    // What replaced it as the live guard is AnchorTests.The_Printed_Part_Carries_No_Core.

    // 🔴 The radial load is centred on the GRID, and the grid sits on the part axis only when the step divides the
    // diameter: the FE sampler starts at −R and rounds the cell count UP, so on Ø11 at the pine rim period the odd
    // divisors add an empty column (/7 walks the centre a quarter step, ≈71 µm; /11 ≈45 µm). The divisors canon
    // quotes radial rows at must come out aligned, or each of those numbers is a lopsided load on another part.
    // The check reads the SAMPLED grid, never re-derives the cell count, so a sampler change moves it too.
    // MUTATION: drop the halving in RadialLoadCentreOffsetMm (`/ 2.0` → `/ 1.0`) ⇒ every aligned row reds.
    [Theory]
    [InlineData(6, false)]
    [InlineData(7, true)]
    [InlineData(8, false)]
    [InlineData(10, false)]
    [InlineData(11, true)]
    [InlineData(12, false)]
    [InlineData(16, false)]
    public void The_Radial_Load_Centre_Sits_On_The_Part_Axis_Only_When_The_Step_Divides_The_Diameter(int nDiv, bool bOffAxis)
    {
        Connectivity.Grid grid = ThinPineSlice(nDiv, out float fOuterRadiusMm);
        double dOffset = VoxelFea.RadialLoadCentreOffsetMm(grid, fOuterRadiusMm);
        if (bOffAxis)
            Assert.True(dOffset > VoxelFea.RadialCentreToleranceMm, $"/{nDiv}: a {dOffset * 1000.0:F2} µm offset must be refused");
        else
            Assert.True(dOffset <= VoxelFea.RadialCentreToleranceMm, $"/{nDiv}: {dOffset * 1000.0:F4} µm off the axis on a divisor canon quotes");
    }

    // The backstop, for a caller that forgets the pre-check the CLI verbs carry: a refusal, never a lopsided number.
    // MUTATION: delete the throw at the top of RadialStiffness ⇒ this solves the slice and reds.
    [Fact]
    public void Radial_Stiffness_Refuses_A_Grid_Whose_Load_Centre_Is_Off_The_Axis()
    {
        Connectivity.Grid grid = ThinPineSlice(7, out float fOuterRadiusMm);
        var ex = Assert.Throws<InvalidOperationException>(() => VoxelFea.RadialStiffness(grid, fOuterRadiusMm));
        Assert.Contains("off the part axis", ex.Message);
    }

    // A few-cell-thick slice of the shipped pine part at the step the CLI would use for this divisor — the finest
    // period, exactly as `fea` derives it — so the pins read the real sampler without paying for a 40 mm part.
    private static Connectivity.Grid ThinPineSlice(int nDiv, out float fOuterRadiusMm)
    {
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { LengthMm = 0.6f };
        float fPeriodMin = cem.GyroidPeriodRimMm > 0f ? MathF.Min(cem.GyroidPeriodMm, cem.GyroidPeriodRimMm) : cem.GyroidPeriodMm;
        fOuterRadiusMm = cem.OuterDiameterMm / 2f;
        return VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Gyroid(cem), cem, fPeriodMin / nDiv);
    }

    // 🔴 Phase lock is a property of the STEP against a CONSTANT period: a whole number of steps per period locks every
    // cell (the --step-div case), a half-step count locks every second cell, a step taken from the diameter (11/50,
    // 11/60 at period 2.0) does not repeat within the part, and a graded period (pine, 2.5 → 2.0) never locks.
    // MUTATION: delete the graded-period early return in PhaseLockCells ⇒ the pine row reports a lock and reds.
    [Theory]
    [InlineData(2.0f, 0f, 0.25f, 1)]
    [InlineData(2.0f, 2.0f, 0.2f, 1)]
    [InlineData(2.0f, 0f, 0.5f, 1)]
    [InlineData(2.0f, 0f, 2.0f / 7.5f, 2)]
    [InlineData(2.0f, 0f, 0.22f, 0)]
    [InlineData(2.0f, 0f, 11f / 60f, 0)]
    [InlineData(2.5f, 2.0f, 0.25f, 0)]
    public void Phase_Lock_Is_Read_From_The_Step_Against_A_Constant_Period_Only(float fCore, float fRim, float fStep, int nExpected)
        => Assert.Equal(nExpected, VoxelFea.PhaseLockCells(fStep, fCore, fRim));

    // 🔴 The staircase itself, on the shipped constant-period part, read through the real sampler with the wall held
    // uniform as `fea --fit` holds it: on a locked step (/8, /10) walls a few hundredths apart sample to ONE grid — at /8
    // so does +0.10 — while a step from the diameter that does not divide the period (0.22 mm) resolves every wall.
    // This is what broke the graded-pair bracket on 2026-09-14, and the guard must see it before any solve.
    // MUTATION: negate the cell comparison in IdenticalSweepGrids (`!a.Cells.SequenceEqual(b.Cells)`) ⇒ this reds.
    // (An early `return aPairs;` is not a usable mutation: it does not compile — CS0162 is an error in this project.)
    [Fact]
    public void A_Constant_Period_Wall_Sweep_Collapses_On_A_Locked_Step_And_Resolves_On_A_Step_From_The_Diameter()
    {
        const float fPeriod = 2.0f;
        List<(float WallA, float WallB)> aLockedD8 = VoxelFea.IdenticalSweepGrids(
            [(-0.15f, GradedPorositySlice(-0.15f, fPeriod / 8)), (-0.08f, GradedPorositySlice(-0.08f, fPeriod / 8)),
             (0.10f, GradedPorositySlice(0.10f, fPeriod / 8))]);
        Assert.Equal(3, aLockedD8.Count);

        List<(float WallA, float WallB)> aLockedD10 = VoxelFea.IdenticalSweepGrids(
            [(-0.15f, GradedPorositySlice(-0.15f, fPeriod / 10)), (-0.08f, GradedPorositySlice(-0.08f, fPeriod / 10))]);
        Assert.Single(aLockedD10);

        List<(float WallA, float WallB)> aUnlocked = VoxelFea.IdenticalSweepGrids(
            [(-0.15f, GradedPorositySlice(-0.15f, 0.22f)), (-0.08f, GradedPorositySlice(-0.08f, 0.22f)),
             (0.10f, GradedPorositySlice(0.10f, 0.22f))]);
        Assert.Empty(aUnlocked);
    }

    // The shipped graded_porosity part (constant period 2.0, Ø11) with the wall made uniform — rim follows core, exactly
    // as FeaFitPart overrides it — as a thin slice, so the pin reads the real field and sampler cheaply.
    private static Connectivity.Grid GradedPorositySlice(float fWall, float fStepMm)
    {
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.graded_porosity.json") with
        {
            LengthMm = 0.6f,
            GyroidWallParam = fWall,
            GyroidWallParamRim = fWall,
        };
        return VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Gyroid(cem), cem, fStepMm);
    }

    // 🔴 The Gibson-Ashby fit has a CLOSED FORM too, and it is the only kind of pin worth writing for
    // a regression: points generated FROM a known C and n must come back as that C and n. A fit is
    // exactly the sort of routine that returns a plausible pair whatever it does — and the pair it
    // returns is about to be quoted as a measured coefficient in canon (01_01 §5.2).
    // MUTATION: in FitPowerLaw drop the mean-centring of `dX` (use `Math.Log(dRho)` raw in dSxx/dSxy)
    // ⇒ the slope stays right and C comes back ~0.18 instead of 0.72, i.e. exactly the half a reader
    // would not notice.
    [Fact]
    public void The_Power_Law_Fit_Recovers_The_Coefficients_It_Was_Given()
    {
        const double dC = 0.72, dN = 2.34;
        double[] aRho = [0.26, 0.30, 0.34, 0.38, 0.44];
        var aPoints = aRho.Select(r => (Density: r, Ratio: dC * Math.Pow(r, dN))).ToList();

        VoxelFea.PowerLaw fit = VoxelFea.FitPowerLaw(aPoints);

        Assert.True(Math.Abs(fit.C - dC) < 1e-9, $"C came back {fit.C:F9} from points generated with {dC}");
        Assert.True(Math.Abs(fit.N - dN) < 1e-9, $"n came back {fit.N:F9} from points generated with {dN}");
        Assert.True(Math.Abs(fit.RSquared - 1.0) < 1e-9, $"noiseless points must fit exactly; R² = {fit.RSquared:F9}");
        Assert.Equal(aRho.Length, fit.Points);
    }

    // The fit must REFUSE the two inputs that would let it report a number it cannot know: a single
    // point (C and n are not separable — any C is reachable by moving n) and a sweep that varied
    // nothing. Both are silent failures otherwise: OLS on one point has no slope to solve, and a
    // zero-variance x gives a division by zero that surfaces as NaN in a JSON cache nobody re-reads.
    [Fact]
    public void The_Power_Law_Fit_Refuses_Inputs_That_Cannot_Separate_C_From_N()
    {
        Assert.Throws<ArgumentException>(() => VoxelFea.FitPowerLaw([(0.35, 0.10)]));
        Assert.Throws<ArgumentException>(() => VoxelFea.FitPowerLaw([(0.35, 0.10), (0.35, 0.11)]));
        Assert.Throws<ArgumentException>(() => VoxelFea.FitPowerLaw([(0.35, 0.0), (0.40, 0.12)]));
    }

    // ── Face-offset dilation (`fea <cem> --dilate`, DilatedField in Zone1Anode.cs, 00_07 HW.51) ──────────────────────
    //
    // 🔑 Each pin holds a property the sensitivity curve's READING depends on, not a baseline of its numbers: an identity
    // at zero, no metal from outside the part, metal on the right side of the part's own frame, porosity that only falls,
    // a declared discretisation shortfall, and cache names that cannot overwrite a pinned measurement.

    private sealed class FieldOf(Func<Vector3, float> fnValue) : IImplicit
    {
        public float fSignedDistance(in Vector3 vecPt) => fnValue(vecPt);
    }

    // 🔴 (а) THE identity control. At zero offset the element is empty and the field returns the lattice's own sign, so
    // the grid must be the intent grid cell for cell — through the same sampler, for BOTH elements. The slice is 0.55 mm
    // long at the committed step, so the grid's last layer is centred PAST the body end (0.583 mm): that layer is exactly
    // what a clipped origin would silently empty, and the counter-lamp proves it holds metal to lose.
    // MUTATION: clip the origin in DilatedField (`bool bSolid = fnInBody(vecPt) && oInner.fSignedDistance(vecPt) < 0f;`) ⇒ reds.
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void A_Zero_Face_Offset_Through_The_Dilation_Samples_The_Intent_Grid_Bit_For_Bit(bool bDownskin)
    {
        DilationMode mode = bDownskin ? DilationMode.Downskin : DilationMode.Isotropic;
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { LengthMm = 0.55f };
        float fStep = 2.0f / 12; // pine's finest period / 12 — the step of the committed dilation sweep
        Connectivity.Grid gridIntent = VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Gyroid(cem), cem, fStep);
        Connectivity.Grid gridZero = VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Dilated(cem, mode, 0f), cem, fStep);

        int kLast = gridIntent.Nz - 1;
        Assert.True((kLast + 0.5f) * fStep > cem.LengthMm, "counter-lamp: the grid's last layer must sit past the body end");
        Assert.Contains(Phase.Solid, Enumerable.Range(0, gridIntent.Nx * gridIntent.Ny).Select(ij => gridIntent.Cells[(ij * gridIntent.Nz) + kLast]));
        Assert.True(gridZero.Cells.SequenceEqual(gridIntent.Cells),
            $"{mode}: a zero face offset through the wrapper changed the sampled grid — the identity the zero row stands on is gone");
    }

    // 🔴 (б) A SHIFTED sample takes metal only from inside the part body. This field is solid everywhere OUTSIDE the pine
    // part — past the rim, inside the rod, below z = 0, above z = L, written out here rather than read from
    // Zone1Anode.Body, so a body predicate that forgets a face is caught — and empty inside it, so a correct dilation adds
    // nothing at all. The counter-lamp runs the same ball UNCLIPPED and must find phantom metal against each of the four
    // faces on its own, or the pin would be green on a field that offers nothing to steal.
    // MUTATION: make the clip a tautology (`(fnInBody(vecAt) || !fnInBody(vecAt)) && …`), or drop the z-bounds in
    // Zone1Anode.Body ⇒ reds. (Deleting the fnInBody call outright is not a usable mutation: the parameter goes unread and
    // CS9113 is an error in this project.)
    [Fact]
    public void An_Isotropic_Dilation_Takes_No_Metal_From_Outside_The_Part_Body()
    {
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { LengthMm = 1.0f };
        const float fStep = 0.25f, fRadius = 0.225f; // 1.0 / 0.25 is exact: no layer is centred past the body end
        float fRInner = Zone1Anode.InnerRadiusMm(cem), fROuter = cem.OuterDiameterMm / 2f, fLength = cem.LengthMm;
        // ⚠️ `fRInner` is 0 since the welded branch (2026-09-18): the part has no bore, so «outside the body»
        // is the rim and the two end faces — three faces, not four. The bore clause stays in the field for
        // the day a part declares a core again, and the face census below counts what actually exists.
        var oOutsideOnly = new FieldOf(v =>
        {
            float fR = MathF.Sqrt((v.X * v.X) + (v.Y * v.Y));
            return fR < fRInner || fR > fROuter || v.Z < 0f || v.Z > fLength ? -1f : 1f;
        });
        Vector3[] aBall = DilatedField.Element(DilationMode.Isotropic, fRadius, Zone1Anode.BuildDirection);

        Connectivity.Grid gridClipped = VoxelFea.SampleAnchorAsBuilt(
            new DilatedField(oOutsideOnly, Zone1Anode.Body(cem), aBall), cem, fStep);
        Assert.DoesNotContain(Phase.Solid, gridClipped.Cells);

        Connectivity.Grid gridUnclipped = VoxelFea.SampleAnchorAsBuilt(
            new DilatedField(oOutsideOnly, _ => true, aBall), cem, fStep);
        var aFacesReached = new HashSet<string>();
        for (int i = 0; i < gridUnclipped.Nx; i++)
            for (int j = 0; j < gridUnclipped.Ny; j++)
                for (int k = 0; k < gridUnclipped.Nz; k++)
                {
                    if (gridUnclipped.Cells[gridUnclipped.Index(i, j, k)] != Phase.Solid) continue;
                    float x = -fROuter + ((i + 0.5f) * fStep), y = -fROuter + ((j + 0.5f) * fStep), z = (k + 0.5f) * fStep;
                    float fR = MathF.Sqrt((x * x) + (y * y));
                    bool bRim = fR > fROuter - fRadius, bBore = fR < fRInner + fRadius;
                    bool bBottom = z < fRadius, bTop = z > fLength - fRadius;
                    if (bRim && !bBore && !bBottom && !bTop) aFacesReached.Add("rim");
                    if (bBore && !bRim && !bBottom && !bTop) aFacesReached.Add("bore");
                    if (bBottom && !bRim && !bBore && !bTop) aFacesReached.Add("z = 0");
                    if (bTop && !bRim && !bBore && !bBottom) aFacesReached.Add("z = L");
                }
        int nFaces = fRInner > 0f ? 4 : 3;   // no bore ⇒ no bore face to steal from
        Assert.True(aFacesReached.Count == nFaces,
            $"counter-lamp: the unclipped ball must steal phantom metal at all {nFaces} faces of this part, " +
            $"reached only [{string.Join(", ", aFacesReached)}]");
    }

    // 🔴 (в) Downskin puts metal on the −BD side of a down-facing face IN THE PART'S OWN FRAME — pinned by where the metal
    // lands, never by the sign of BuildDirection (picogk #15). The frame is read from the shipped stack: the Zone-2 sleeve
    // reaches the anode from ONE end, so the other end is the tree-side tip, and 01_02 §1.6 prints the anode tip-DOWN. A
    // horizontal slab of metal must therefore grow toward that tip by exactly the offset, and gain no layer on the far side.
    // MUTATION: `BuildDirection = -Vector3.UnitZ` (or a negated segment in DilatedField.Element) ⇒ the metal lands on the
    // capsule side of the slab and this reds.
    [Fact]
    public void A_Downskin_Dilation_Grows_Metal_Toward_The_Tip_The_Part_Is_Printed_On()
    {
        AnchorAxialStackCem stack = Cem.Parse<AnchorAxialStackCem>(
            File.ReadAllText(Path.Combine(CemFixtures.Dir(), "anchor_axial_stack.json")));
        float fSleeveBottom = AxialStack.SleeveBottomZMm(stack);
        // The sleeve's lower end sits above z = 0 and below the anode top, so it rides the z = L end: the uncovered end,
        // z = 0, is the tree-side tip — the end tip-down printing puts on the plate.
        Assert.True(fSleeveBottom > 0f && fSleeveBottom < stack.Zone1.LengthMm,
            $"the Zone-2 sleeve must reach the anode from its z = L end only (its lower end sits at z = {fSleeveBottom} mm)");

        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { LengthMm = 2.0f };
        const float fStep = 0.125f, fLength = 0.25f, fSlabLo = 0.75f, fSlabHi = 1.25f;
        var oSlab = new FieldOf(v => v.Z >= fSlabLo && v.Z < fSlabHi ? -1f : 1f);
        Connectivity.Grid grid = VoxelFea.SampleAnchorAsBuilt(
            new DilatedField(oSlab, Zone1Anode.Body(cem), DilatedField.Element(DilationMode.Downskin, fLength, Zone1Anode.BuildDirection)),
            cem, fStep);

        const float fLo = fSlabLo - fLength, fHi = fSlabHi; // the slab plus the band on its tip side
        for (int k = 0; k < grid.Nz; k++)
        {
            float fZ = (k + 0.5f) * fStep;
            bool bSolidLayer = Enumerable.Range(0, grid.Nx * grid.Ny).Any(ij => grid.Cells[(ij * grid.Nz) + k] == Phase.Solid);
            Assert.True(bSolidLayer == (fZ >= fLo && fZ < fHi),
                $"layer z = {fZ:F4} mm is {(bSolidLayer ? "solid" : "empty")}, but a downskin of {fLength} mm printed tip-down " +
                $"must fill exactly [{fLo}, {fHi}) — the slab plus the band on its TIP side");
        }
    }

    // 🔴 (г) Porosity never rises with the face offset — a dilation only adds metal — and the first non-zero offset must
    // already lower it, or the sweep measured the zero row twice. Read on a real pine slice for both elements, at the
    // offsets the verb sweeps by default.
    // MUTATION: drop `&& !bSolid` from DilatedField's loop — the field keeps the LAST sample instead of ANY, i.e. it
    // TRANSLATES the lattice rather than dilating it, and the clipped band at the far end empties ⇒ both rows red.
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Porosity_Never_Rises_With_The_Face_Offset(bool bDownskin)
    {
        DilationMode mode = bDownskin ? DilationMode.Downskin : DilationMode.Isotropic;
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { LengthMm = 1.0f };
        const float fStep = 0.25f;
        float[] aOffsets = Program.DefaultFaceOffsetsMm(mode);
        Assert.Equal(0f, aOffsets[0]);
        double[] aPorosity = [.. aOffsets.Select(f => Connectivity.Porosity(
            VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Dilated(cem, mode, f), cem, fStep)))];

        Assert.True(aPorosity[1] < aPorosity[0],
            $"{mode}: a {aOffsets[1]} mm face offset left porosity at {aPorosity[1]:P3} (zero row {aPorosity[0]:P3}) — the sweep varied nothing");
        for (int i = 1; i < aPorosity.Length; i++)
            Assert.True(aPorosity[i] <= aPorosity[i - 1],
                $"{mode}: porosity ROSE from {aPorosity[i - 1]:P3} at {aOffsets[i - 1]} mm to {aPorosity[i]:P3} at {aOffsets[i]} mm — a dilation cannot remove metal");
    }

    // ⚖️ (д) The discretisation's DECLARED ceiling, in closed form: a half-space of metal dilated through the element.
    // Downskin must be EXACT — a face tilted θ from straight down moves by L·cos θ, vertical and upward faces not at all.
    // Isotropic must never overshoot R and may fall short by at most 0.6 % of R on any face (measured 0.49 %, DilatedField).
    // MUTATION: drop the OuterShellMinDirections floor ⇒ R = 0.05 (79 directions, ~4.7 % short) and R = 0.125 (491) red,
    // R = 0.225 (1 591 of its own) stays green; stretch the shells to 1.01·R ⇒ the overshoot half reds on every radius.
    [Theory]
    [InlineData(true, 0.10f)]
    [InlineData(true, 0.45f)]
    [InlineData(false, 0.05f)]
    [InlineData(false, 0.125f)]
    [InlineData(false, 0.225f)]
    public void Dilation_Falls_Short_On_A_Flat_Face_By_A_Declared_Fraction_Only(bool bDownskin, float fOffset)
    {
        DilationMode mode = bDownskin ? DilationMode.Downskin : DilationMode.Isotropic;
        const double dIsoShortfall = 0.006, dEdge = 1e-4;
        Vector3[] aElement = DilatedField.Element(mode, fOffset, Zone1Anode.BuildDirection);
        var rng = new Random(20260914);
        for (int n = 0; n < 4000; n++)
        {
            double dZ = (2.0 * rng.NextDouble()) - 1.0, dPhi = 2.0 * Math.PI * rng.NextDouble(), dRho = Math.Sqrt(1.0 - (dZ * dZ));
            var vecNormal = new Vector3((float)(dRho * Math.Cos(dPhi)), (float)(dRho * Math.Sin(dPhi)), (float)dZ);
            // Metal where x·n < 0: a flat face whose OUTWARD normal is n.
            var oField = new DilatedField(new FieldOf(v => Vector3.Dot(v, vecNormal)), _ => true, aElement);
            double dReach = mode == DilationMode.Downskin
                ? fOffset * Math.Max(0.0, -Vector3.Dot(Zone1Anode.BuildDirection, vecNormal))
                : fOffset;
            double dShort = mode == DilationMode.Downskin ? dEdge * fOffset : dIsoShortfall * fOffset;

            if (dReach > 2.0 * dShort)
                Assert.True(oField.fSignedDistance(vecNormal * (float)(dReach - dShort)) < 0f,
                    $"{mode} {fOffset} mm: a point {dReach - dShort:E3} mm off a face with normal {vecNormal} stayed empty — the element falls short by more than declared");
            Assert.True(oField.fSignedDistance(vecNormal * (float)(dReach + (dEdge * fOffset))) > 0f,
                $"{mode} {fOffset} mm: a point {dReach + (dEdge * fOffset):E3} mm off a face with normal {vecNormal} turned solid — the element reaches PAST its own length");
        }
    }

    // 🔴 (ґ) A dilation cache name can never land on a pinned file, nor on another dilation row. The other `fea` families'
    // committed files are read from the directory itself, never from a roster, and every name the verb can write for a
    // shipped anchor — both elements, every offset either element sweeps by default, each committed step token, rod or not
    // — must miss all of them and be unique along every axis a row differs on. The zero offset is the one row both elements
    // share by construction (the wrapper is the identity there), so it is keyed without its element.
    // MUTATION: return `$"{strCemName}.json"` from Program.DilationCacheName ⇒ lands on anchor_zone1_pine.json and reds;
    // drop the element token ⇒ downskin and iso at one offset share a file and the uniqueness half reds.
    [Fact]
    public void Dilation_Cache_Names_Never_Land_On_A_Pinned_File_Or_On_Each_Other()
    {
        string strCache = Path.Combine(Path.GetDirectoryName(CemFixtures.Dir())!, "cache", "fea");
        HashSet<string> aPinned = [.. Directory.GetFiles(strCache, "*.json")
            .Select(p => Path.GetFileName(p))
            .Where(n => !n.StartsWith("dilation_sensitivity.", StringComparison.Ordinal))];
        Assert.Contains("anchor_zone1_pine.json", aPinned); // counter-lamp: the pinned step sweep is in the set

        float[] aOffsets = [.. Enum.GetValues<DilationMode>().SelectMany(Program.DefaultFaceOffsetsMm).Distinct()];
        (int Div, float StepMm)[] aSteps = [(6, 0f), (7, 0f), (8, 0f), (10, 0f), (12, 0f), (16, 0f), (0, 11f / 60f), (0, 0.22f)];
        var oRowOfName = new Dictionary<string, string>();
        foreach (string strCem in CemFixtures.AnchorFiles().Select(f => CemFixtures.Anchor(f).Name))
            foreach (DilationMode mode in Enum.GetValues<DilationMode>())
                foreach (float fOffset in aOffsets)
                    foreach ((int nDiv, float fStepMm) in aSteps)
                        {
                            string strName = Program.DilationCacheName(strCem, mode, fOffset, nDiv, fStepMm);
                            Assert.DoesNotContain(strName, aPinned);
                            string strRow = $"{strCem} · {(fOffset == 0f ? "no element" : mode)} · {fOffset} mm · /{nDiv} · {fStepMm} mm";
                            Assert.True(oRowOfName.TryAdd(strName, strRow) || oRowOfName[strName] == strRow,
                                $"{strName} would be written by two different rows: {oRowOfName.GetValueOrDefault(strName)} and {strRow}");
                        }
    }
}
