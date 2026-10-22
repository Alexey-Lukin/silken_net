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
    // 11/60 at period 2.0) does not repeat within the part, and a graded period (pine, 2.5 → 2.0) never locks IN-PLANE
    // (along z it does since HW.33 (в) — the next test).
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

    // 🔴 ⊕ HW.33 (в): the graded pine part is constant-period ALONG z, so every step of its pinned sweep (rim/N) locks
    // the axis every cell while PhaseLockCells stays 0, and a step from the diameter locks neither; the stepped part has
    // no single axial period. Read through the real manifests and the generator's own rule.
    // MUTATION: make Zone1Anode.AxialPeriodMm return the CORE period ⇒ /6 reads a two-cell repeat (2.5 / (2.0/6) = 7.5) and reds.
    [Theory]
    [InlineData("anchor_zone1.pine.json", 6, 1)]
    [InlineData("anchor_zone1.pine.json", 8, 1)]
    [InlineData("anchor_zone1.pine.json", 12, 1)]
    [InlineData("anchor_zone1.pine.json", 16, 1)]
    [InlineData("anchor_zone1.pine.json", -50, 0)]
    [InlineData("anchor_zone1.pine.json", -60, 0)]
    [InlineData("anchor_zone1.stepped.json", 8, 0)]
    public void The_Graded_Part_Locks_Along_The_Axis_On_Its_Own_Sweep_Steps(string strCem, int nDiv, int nExpected)
    {
        AnchorCem cem = CemFixtures.Anchor(strCem);
        float fPeriodMin = cem.GyroidPeriodRimMm > 0f ? MathF.Min(cem.GyroidPeriodMm, cem.GyroidPeriodRimMm) : cem.GyroidPeriodMm;
        float fStep = nDiv > 0 ? fPeriodMin / nDiv : cem.OuterDiameterMm / -nDiv;      // < 0: a step from the diameter
        Assert.Equal(nExpected, VoxelFea.AxialPhaseLockCells(fStep, Zone1Anode.AxialPeriodMm(cem)));
        Assert.Equal(0, VoxelFea.PhaseLockCells(fStep, cem.GyroidPeriodMm, cem.GyroidPeriodRimMm));
    }

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
        AnchorAxialStackCem stack = AxialStack.Load(Path.Combine(CemFixtures.Dir(), "anchor_axial_stack.json"));
        float fSleeveBottom = AxialStack.SleeveBottomZMm(stack);
        // Since G1 (2026-10-12) the sleeve's lower end sits EXACTLY on the gyroid-to-shank junction (z = the gyroid's length),
        // so it rides the z = L end of the gyroid: the uncovered end, z = 0, is the tree-side tip — the end tip-down printing
        // puts on the plate. Equality, not a range: a range was true by construction once the shank inserts whole.
        Assert.True(fSleeveBottom > 0f, $"the Zone-2 sleeve must reach the anode from its z = L end only (z = {fSleeveBottom} mm)");
        Assert.Equal(stack.Zone1.LengthMm, fSleeveBottom, 3);

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

    // ── Periodic homogenisation (`fea --periodic`, VoxelFea.PeriodicHomogenization, 00_07 HW.23) ─────────────────────
    //
    // 🔑 Same shape as the rest of this file: every pin is a case whose answer is known before the solve, so the tensor
    // `106` is to read its C44 from, and the field `105` its peak from, are proven right, not merely stable.

    private static Connectivity.Grid Box(int nx, int ny, int nz, float fStepMm, Func<int, int, int, bool> fnSolid)
    {
        var aCells = new Phase[nx * ny * nz];
        var grid = new Connectivity.Grid(aCells, nx, ny, nz, fStepMm);
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                    aCells[grid.Index(i, j, k)] = fnSolid(i, j, k) ? Phase.Solid : Phase.Pore;
        return grid;
    }

    // 🔴 THE calibration of the periodic case. A fully solid cell takes every macro strain homogeneously — the fluctuation
    // is zero and the load K·(E·x) cancels at every node of the torus — so the tensor must be the solid's own, entry for
    // entry, to round-off. One number per entry checks the wrap, the load assembly, the Gauss-point stress average and the
    // cell-volume convention together.
    // MUTATION: mesh the cell OPEN (`Build` for `BuildPeriodic`) ⇒ the far faces carry an unbalanced load, the fluctuation
    // relaxes them, and the cell's rotations are left unpinned — the tensor leaves the solid's.
    // ⚠️ Blind by construction to a CONSISTENTLY twisted gluing of the faces: any consistent gluing of a solid cell admits the
    // same homogeneous solution. The two-period and cubic pins below are the ones a twist would break.
    [Fact]
    public void A_Solid_Period_Cell_Returns_The_Solid_Tensor_Exactly()
    {
        VoxelFea.PeriodicResult r = VoxelFea.PeriodicHomogenization(Box(4, 4, 6, 0.25f, (_, _, _) => true));
        double[,] aD = VoxelFea.IsotropicStiffness(VoxelFea.SolidPoissonRatio);
        Assert.True(r.Converged);
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
                Assert.True(Math.Abs(r.C[i, j] - aD[i, j]) < 1e-12,
                    $"C[{i},{j}] = {r.C[i, j]:F12} against the solid's {aD[i, j]:F12} — a homogeneous field has no discretisation error");
    }

    // 🔴 The non-trivial closed form: a periodic SLAB (solid layers in a pore matrix, stacked along z). In-plane the
    // layers are free on both faces, so any in-plane strain puts them in PLANE STRESS — they must contract through their
    // thickness, a fluctuation the solver has to find — and the cell carries the plane-stress stiffness times the solid
    // fraction; across the layers it carries nothing at all. Exact for trilinear hexes (every field is linear), so it
    // checks the wrap in x and y, the fluctuation, the load and the average at once.
    // MUTATION: drop the macro-strain load (`aLoad` all zero) ⇒ the fluctuation is zero, the layers keep ε_zz = 0 and the
    // in-plane entries read the plane-STRAIN stiffness (λ + 2μ)·φ instead.
    [Fact]
    public void A_Periodic_Slab_Reads_Plane_Stress_Times_Its_Fraction_And_Nothing_Across()
    {
        const double dFraction = 0.5;
        VoxelFea.PeriodicResult r = VoxelFea.PeriodicHomogenization(
            Box(4, 4, 8, 0.25f, (_, _, k) => k is >= 2 and < 6), dTol: 1e-12);
        double nu = VoxelFea.SolidPoissonRatio, dMu = 1.0 / (2.0 * (1.0 + nu));
        double dPlane = dFraction / (1.0 - (nu * nu));
        Assert.True(r.Converged);
        (int I, int J, double Expected, string What)[] aCases =
        [
            (0, 0, dPlane, "C11 = φ·E/(1 − ν²)"), (1, 1, dPlane, "C22"), (0, 1, dPlane * nu, "C12 = φ·νE/(1 − ν²)"),
            (5, 5, dFraction * dMu, "C66 = φ·μ"), (2, 2, 0.0, "C33 — nothing across the layers"),
            (3, 3, 0.0, "C44"), (4, 4, 0.0, "C55"), (0, 2, 0.0, "C13"),
        ];
        foreach ((int i, int j, double dExpected, string strWhat) in aCases)
            Assert.True(Math.Abs(r.C[i, j] - dExpected) < 1e-9,
                $"{strWhat}: C[{i},{j}] = {r.C[i, j]:F12}, the closed form gives {dExpected:F12}");
    }

    // 🔴 A ligament the cell boundary cuts is ONE body with its continuation on the far face. Two pieces that touch only
    // through the wrap must be kept together on the torus and split without it.
    // MUTATION: drop the wrap terms in Connectivity.LargestComponentMask (`bPeriodic ? c + nWrapI : -1` → `-1`) ⇒ reds.
    [Fact]
    public void The_Periodic_Mask_Keeps_A_Body_That_Is_Whole_Only_Across_The_Wrap()
    {
        Connectivity.Grid grid = Box(8, 2, 2, 0.25f, (i, _, _) => i is 0 or 1 or 7);
        int nPeriodic = Connectivity.LargestComponentMask(grid, Phase.Solid, bPeriodic: true).Count(b => b);
        int nOpen = Connectivity.LargestComponentMask(grid, Phase.Solid).Count(b => b);
        Assert.Equal(12, nPeriodic); // i = 7 wraps onto i = 0: one body of three layers
        Assert.Equal(8, nOpen);      // without the wrap the two-layer piece is the largest
    }

    // 🔴 The cell is ONE period of an infinite lattice, so two periods are the same lattice: their tensors must agree to the
    // solver's precision. A seam the wrap fails to glue cuts the lattice into slabs one cell thick, and a one-period cell and a
    // two-period cell then hold slabs of different thickness. (The slab pin above never wraps in z — its seams are pore — so
    // this and the solid-cell pin are the two that hold the z seam.)
    // ⚠️ Relabelling the torus (`(i + 1) % nx` for `i % nx`) is NOT a defect this can see, and must not be listed as one: it
    // renames every node consistently, so the mesh is the same lattice and the tensor does not move.
    // MUTATION: cut the z seam in BuildPeriodic (`k % nz` → `Math.Min(k, nz - 1)`) ⇒ the two cells disagree and this reds.
    [Fact]
    public void One_Period_And_Two_Periods_Of_The_Gyroid_Give_One_Tensor()
    {
        VoxelFea.PeriodicResult rOne = VoxelFea.PeriodicHomogenization(VoxelFea.SampleLatticeCube(2.0f, 0.10f, bNetwork: true, 1, 8), dTol: 1e-11);
        VoxelFea.PeriodicResult rTwo = VoxelFea.PeriodicHomogenization(VoxelFea.SampleLatticeCube(2.0f, 0.10f, bNetwork: true, 2, 8), dTol: 1e-11);
        Assert.True(rOne.Converged && rTwo.Converged);
        Assert.True(Math.Abs(rOne.SolidFraction - rTwo.SolidFraction) < 1e-12, "two periods of one lattice hold the same metal fraction");
        double dScale = rOne.C[0, 0];
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
                Assert.True(Math.Abs(rOne.C[i, j] - rTwo.C[i, j]) < 1e-7 * dScale,
                    $"C[{i},{j}]: one period {rOne.C[i, j]:F10}, two periods {rTwo.C[i, j]:F10}");
    }

    // 🔴 The gyroid's cyclic axis permutation (x, y, z) → (y, z, x) maps the lattice onto itself, so it maps the SAMPLED grid
    // onto itself too — checked first, cell for cell, because a tensor pin on a grid that is not symmetric would be judging the
    // sampler — and then the three cubic families of the tensor must be flat to the solver's precision, with the averaged
    // stress matching the strain energy (Hill–Mandel) and every pair of solves reciprocal.
    // ⚠️ Hill–Mandel is an IDENTITY of the formulation (CG from zero keeps the iterate orthogonal to its residual), so its
    // assert catches a stress readout inconsistent with the energy — never a wrong solution; the closed forms above hold that.
    // MUTATION: swap two Voigt shear rows in StrainDisplacementAt (γ_yz ⇄ γ_zx) ⇒ the shear family splits and the readout no
    // longer matches the energy.
    [Fact]
    public void The_Gyroid_Period_Cell_Is_Cubic_And_Its_Stress_Matches_Its_Energy()
    {
        Connectivity.Grid grid = VoxelFea.SampleLatticeCube(2.0f, 0.10f, bNetwork: true, 1, 12);
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
                for (int k = 0; k < grid.Nz; k++)
                    Assert.Equal(grid.Cells[grid.Index(i, j, k)], grid.Cells[grid.Index(j, k, i)]);

        VoxelFea.PeriodicResult r = VoxelFea.PeriodicHomogenization(grid, dTol: 1e-11);
        VoxelFea.CubicReading cubic = VoxelFea.Cubic(r.C);
        Assert.True(r.Converged);
        Assert.True(cubic.EquivalentSpread < 1e-7, $"a cubic family spreads by {cubic.EquivalentSpread:E2}");
        Assert.True(r.HillMandelWorst < 1e-9, $"averaged stress against strain energy: {r.HillMandelWorst:E2}");
        Assert.True(r.ReciprocityWorst < 1e-9, $"C is not symmetric: {r.ReciprocityWorst:E2}");
        Assert.True(cubic.C44 > 0.0 && cubic.C11 > cubic.C12, "a stable cubic body has C44 > 0 and C11 > C12");
    }

    // 🔴 The field reading on the case where the field is known everywhere: a solid cell under a unit uniaxial stress at any
    // angle is uniform — every Gauss point carries exactly that stress, so its largest principal stress, its von Mises and
    // the energy-equivalent RMS are all 1, and the modulus along the direction is E_solid.
    // MUTATION: superpose the six fields with the macro STRESS instead of the macro strain (`aSigmaMacro[k]` for
    // `aStrainMacro[k]`) ⇒ the field is no longer uniaxial and the quantiles leave 1.
    [Fact]
    public void A_Solid_Cell_Under_Uniaxial_Stress_Reads_A_Uniform_Unit_Field()
    {
        VoxelFea.PeriodicResult r = VoxelFea.PeriodicHomogenization(Box(4, 4, 4, 0.25f, (_, _, _) => true), [30.0]);
        VoxelFea.UniaxialField f = Assert.Single(r.Fields);
        Assert.True(Math.Abs(f.ModulusRatio - 1.0) < 1e-12, $"E along 30° = {f.ModulusRatio:F12} of E_solid");
        Assert.True(Math.Abs(f.SigmaWPerMacroStress - 1.0) < 1e-12, $"σ_W = {f.SigmaWPerMacroStress:F12} for a unit stress");
        foreach (double q in f.PrincipalOverSigmaW.Concat(f.VonMisesOverSigmaW))
            Assert.True(Math.Abs(q - 1.0) < 1e-9, $"a uniform field read a quantile of {q:F12} over σ_W");
        Assert.True(f.EnergyIdentityResidual < 1e-12);
    }

    // 🔴 On the real lattice the field is NOT uniform, and the check that it is the right field is energetic: the Gauss-point
    // energy of the superposed field, over the metal and back to the cell, must equal the macro energy the tensor gives
    // (½·Σ²/E_dir) — a superposition with wrong coefficients, or a stress read at points the element matrix does not integrate,
    // breaks it. Along the cube axis the modulus must also be the cubic reading's E[100], and RMS can never exceed the peak.
    // MUTATION: read the field at the element CENTROID instead of the eight Gauss points ⇒ the averaged strain loses its
    // bending part and the energy falls short of the tensor's; drop `Array.Sort(aPrincipal)` ⇒ the quantiles stop ascending.
    [Fact]
    public void The_Gyroid_Field_Energy_Reproduces_The_Tensor_It_Was_Superposed_From()
    {
        VoxelFea.PeriodicResult r = VoxelFea.PeriodicHomogenization(
            VoxelFea.SampleLatticeCube(2.0f, 0.10f, bNetwork: true, 1, 12), [0.0, 45.0], dTol: 1e-11);
        VoxelFea.CubicReading cubic = VoxelFea.Cubic(r.C);
        foreach (VoxelFea.UniaxialField f in r.Fields)
        {
            Assert.True(f.EnergyIdentityResidual < 1e-8, $"θ = {f.ThetaDeg}: field energy against the tensor's, {f.EnergyIdentityResidual:E2}");
            // Canon quotes p50…p99.9 from this field, so the quantiles themselves are pinned: ascending, straddling the RMS on a
            // field that is not uniform, and consistent with the share of metal above the RMS.
            double[] q = f.PrincipalOverSigmaW;
            for (int i = 1; i < q.Length; i++)
                Assert.True(q[i] >= q[i - 1], $"θ = {f.ThetaDeg}: quantile {VoxelFea.FieldQuantiles[i]} reads {q[i]:F4} below its predecessor {q[i - 1]:F4} — the sample is not sorted");
            Assert.True(q[0] < 1.0 && q[^1] > 1.0, $"θ = {f.ThetaDeg}: a non-uniform field must have its median below the RMS and its peak above");
            int iFirstAbove = Array.FindIndex(q, x => x > 1.0);
            Assert.True(f.ShareAboveSigmaW <= 1.0 - VoxelFea.FieldQuantiles[iFirstAbove - 1] + 1e-12 && f.ShareAboveSigmaW > 0.0,
                $"θ = {f.ThetaDeg}: {f.ShareAboveSigmaW:P2} of the metal above the RMS is inconsistent with quantile {VoxelFea.FieldQuantiles[iFirstAbove - 1]} at {q[iFirstAbove - 1]:F4}");
        }
        Assert.True(Math.Abs((r.Fields[0].ModulusRatio / cubic.E100) - 1.0) < 1e-7,
            $"E along [100] from the field {r.Fields[0].ModulusRatio:F10} against the cubic reading {cubic.E100:F10}");
        Assert.True(Math.Abs((r.Fields[1].ModulusRatio / cubic.E110) - 1.0) < 1e-7,
            $"E along [110] from the field {r.Fields[1].ModulusRatio:F10} against the cubic reading {cubic.E110:F10}");
    }

    // The closed-form principal stresses keep the three invariants of any symmetric tensor: the trace, the squared norm and
    // the determinant — a sign or a phase slip in the trigonometric form breaks at least one.
    // MUTATION: take the middle root as `dQ − dS1 − dS3` (drop the factor 3) ⇒ the trace reds.
    [Fact]
    public void Principal_Stresses_Keep_The_Three_Invariants()
    {
        var rng = new Random(20261021);
        for (int n = 0; n < 2000; n++)
        {
            double[] s = [.. Enumerable.Range(0, 6).Select(_ => (2.0 * rng.NextDouble()) - 1.0)];
            (double s1, double s2, double s3) = VoxelFea.PrincipalStresses(s);
            Assert.True(s1 >= s2 && s2 >= s3, "principal stresses must come back ordered");
            double dTrace = s[0] + s[1] + s[2];
            double dNorm = (s[0] * s[0]) + (s[1] * s[1]) + (s[2] * s[2]) + (2.0 * ((s[3] * s[3]) + (s[4] * s[4]) + (s[5] * s[5])));
            double dDet = (s[0] * ((s[1] * s[2]) - (s[3] * s[3]))) - (s[5] * ((s[5] * s[2]) - (s[3] * s[4]))) + (s[4] * ((s[5] * s[3]) - (s[1] * s[4])));
            Assert.True(Math.Abs(s1 + s2 + s3 - dTrace) < 1e-12, "trace");
            Assert.True(Math.Abs((s1 * s1) + (s2 * s2) + (s3 * s3) - dNorm) < 1e-11, "squared norm");
            Assert.True(Math.Abs((s1 * s2 * s3) - dDet) < 1e-11, "determinant");
        }
    }

    // The two refusals: an odd cell count glues two elements of one colour across the wrap (a data race in the scatter), and
    // an Outside cell means the grid is a specimen with a boundary, not a period cell.
    [Fact]
    public void The_Periodic_Case_Refuses_An_Odd_Cell_Count_And_An_Outside_Cell()
    {
        Assert.Throws<ArgumentException>(() => VoxelFea.PeriodicHomogenization(Box(4, 4, 5, 0.25f, (_, _, _) => true)));
        Connectivity.Grid grid = Box(4, 4, 4, 0.25f, (_, _, _) => true);
        grid.Cells[0] = Phase.Outside;
        Assert.Throws<ArgumentException>(() => VoxelFea.PeriodicHomogenization(grid));
    }

    // 🔴 A periodic cache name carries topology, wall level and cell count, never lands on a committed file of another
    // family, and refuses a level it would have to round (two levels on one file is the quiet overwrite of picogk gotcha #14).
    // ⚠️ The period and the field angles are NOT in the name: fea_canon_sync holds the period against the cube ladder and
    // each field row by its angle, so a run at another period or angle set reds the gate rather than this pin.
    // MUTATION: drop the cell token from Program.PeriodicCacheName ⇒ one and two cells share a file and the uniqueness half reds.
    [Fact]
    public void Periodic_Cache_Names_Carry_Topology_Wall_And_Cells_And_Never_Land_On_Another_Family()
    {
        string strCache = Path.Combine(Path.GetDirectoryName(CemFixtures.Dir())!, "cache", "fea");
        HashSet<string> aOthers = [.. Directory.GetFiles(strCache, "*.json").Select(p => Path.GetFileName(p))
            .Where(n => !n.StartsWith("periodic_homogenization.", StringComparison.Ordinal))];
        Assert.Contains("anchor_zone1_pine.json", aOthers); // counter-lamp: the pinned part sweep is in the set

        var oRowOfName = new Dictionary<string, string>();
        foreach (bool bSheet in new[] { false, true })
            foreach (float fWall in new[] { -0.40f, -0.15f, 0.0f, 0.05f, 0.10f, 0.60f })
                foreach (int nCells in new[] { 1, 2, 3 })
                {
                    string strName = Program.PeriodicCacheName(bSheet, fWall, nCells)!;
                    Assert.DoesNotContain(strName, aOthers);
                    string strRow = $"{(bSheet ? "sheet" : "network")} · {fWall} · {nCells}";
                    Assert.True(oRowOfName.TryAdd(strName, strRow), $"{strName} would hold two rows: {oRowOfName.GetValueOrDefault(strName)} and {strRow}");
                }
        Assert.Null(Program.PeriodicCacheName(false, 0.1005f, 1));
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
