// SPDX-License-Identifier: AGPL-3.0-or-later
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

    // The rod is invisible to the gyroid SDF (01_01 §1.4), so it can only enter by being forced
    // solid. If that override were dropped the part would be measured without its own load path.
    [Fact]
    public void The_Monolithic_Rod_Enters_Only_Through_The_Override()
    {
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json");
        Assert.True(cem.BusRodDiameterMm > 0f, "this fixture must declare a rod for the pin to mean anything");

        Connectivity.Grid gridNoRod = VoxelFea.SampleAnchorAsBuilt(
            Zone1Anode.Gyroid(cem), cem, 0.5f, bWithRod: false);
        Connectivity.Grid gridRod = VoxelFea.SampleAnchorAsBuilt(
            Zone1Anode.Gyroid(cem), cem, 0.5f, bWithRod: true);

        Assert.True(Connectivity.Porosity(gridRod) < Connectivity.Porosity(gridNoRod),
            "adding a solid core must lower the measured porosity of the sampled envelope");
    }
}
