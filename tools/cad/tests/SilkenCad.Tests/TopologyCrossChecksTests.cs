// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// ARCH.25 nice-to-have residual (Euler-χ / tortuosity / as-printed voxel cross-check). Pure-logic,
// no PicoGK Library.Go — same discipline as AnchorTests.cs's connectivity block.
public class TopologyCrossChecksTests
{
    private static Connectivity.Grid MakeGrid(Phase[] cells, int nx, int ny, int nz, float step = 0.1f)
        => new(cells, nx, ny, nz, step);

    // --- Euler characteristic: hand-verifiable golden cases (χ known from first principles) ---

    [Fact]
    public void Euler_Of_A_Single_Solid_Voxel_Is_One()
    {
        // A single closed unit cube: V=8, E=12, F=6, C=1 ⇒ χ = 8-12+6-1 = 1 (contractible ball).
        Connectivity.Grid grid = MakeGrid([Phase.Solid], 1, 1, 1);
        ConnectivityMetrics conn = Connectivity.Analyse(grid);
        var r = TopologyCrossChecks.EulerCrossCheck(grid, conn);

        Assert.Equal(1, r.EulerCharacteristic);
        Assert.Equal(1, r.Components);   // b0 = 1
        Assert.Equal(0, r.Cavities);     // b2 = 0 (no pore at all in this grid)
        Assert.Equal(0, r.Handles);      // b1 = b0 + b2 - χ = 1 + 0 - 1 = 0 (no tunnels — correct, it's a solid cube)
        Assert.True(r.Sound);
    }

    [Fact]
    public void Euler_Of_Two_Disjoint_Solid_Voxels_Is_Two()
    {
        // Two solid voxels separated by a pore gap (no shared face/edge/vertex) ⇒ χ = 2·1 = 2, b0=2, b1=0.
        Connectivity.Grid grid = MakeGrid([Phase.Solid, Phase.Pore, Phase.Solid], 3, 1, 1);
        ConnectivityMetrics conn = Connectivity.Analyse(grid);
        var r = TopologyCrossChecks.EulerCrossCheck(grid, conn);

        Assert.Equal(2, r.EulerCharacteristic);
        Assert.Equal(2, r.Components);
        Assert.Equal(0, r.Handles);
        Assert.True(r.Sound);
    }

    [Fact]
    public void Euler_Of_A_Hollow_Box_Shell_Is_Two_With_One_Cavity()
    {
        // A 3×3×3 solid cube with its centre voxel hollowed out ⇒ one enclosed cavity (b2=1), still
        // simply-connected (b1=0, a shell has no tunnels) ⇒ χ = b0 - b1 + b2 = 1 - 0 + 1 = 2.
        var cells = new Phase[27];
        Array.Fill(cells, Phase.Solid);
        // centre index (1,1,1) in a 3×3×3 grid, Index(i,j,k) = ((i*ny)+j)*nz+k, ny=nz=3 ⇒ ((1*3)+1)*3+1 = 13
        cells[13] = Phase.Pore;
        Connectivity.Grid grid = MakeGrid(cells, 3, 3, 3);
        ConnectivityMetrics conn = Connectivity.Analyse(grid);
        var r = TopologyCrossChecks.EulerCrossCheck(grid, conn);

        Assert.Equal(1, r.Components);
        Assert.Equal(1, r.Cavities);
        Assert.Equal(2, r.EulerCharacteristic);
        Assert.Equal(0, r.Handles);
        Assert.True(r.Sound);
    }

    [Fact]
    public void Euler_Cross_Check_Is_Sound_On_A_Real_Sampled_Anchor()
    {
        // The realistic-geometry sanity test: whatever the sheet gyroid's actual genus is, the
        // cross-check must be internally consistent (Handles >= 0), never merely "some number".
        AnchorCem cem = new() { OuterDiameterMm = 6f, BoreDiameterMm = 1.0f, LengthMm = 6f, GyroidPeriodMm = 1.5f };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStepMm: 0.15f);
        ConnectivityMetrics conn = Connectivity.Analyse(grid);
        var r = TopologyCrossChecks.EulerCrossCheck(grid, conn);

        Assert.True(r.Sound, $"Euler-χ / flood-fill disagree: b0={r.Components} b2={r.Cavities} χ={r.EulerCharacteristic} ⇒ b1={r.Handles}");
    }

    // --- Tortuosity: a 1-voxel-wide straight tunnel has exactly ONE possible path ⇒ τ = 1.0 exactly ---

    [Fact]
    public void Tortuosity_Of_A_Straight_One_Wide_Tunnel_Is_Exactly_One()
    {
        var cells = new Phase[10];
        Array.Fill(cells, Phase.Pore);
        Connectivity.Grid grid = MakeGrid(cells, 1, 1, 10, step: 0.2f);

        var r = TopologyCrossChecks.EstimateAxialTortuosity(grid, nWalkers: 5, seed: 42);

        Assert.Equal(5, r.Successes);
        Assert.NotNull(r.MeanTortuosity);
        Assert.Equal(1.0, r.MeanTortuosity!.Value, 6);
        Assert.Equal(1.0, r.MinTortuosity!.Value, 6);
        Assert.Equal(1.0, r.MaxTortuosity!.Value, 6);
    }

    [Fact]
    public void Tortuosity_On_A_Widened_Tunnel_Is_Never_Below_One()
    {
        // A wider tunnel gives the walker lateral freedom ⇒ actual path ≥ straight-line displacement,
        // always (never < 1 — that would be a bug: no path can be shorter than the straight line).
        var cells = new Phase[3 * 3 * 12];
        Array.Fill(cells, Phase.Pore);
        Connectivity.Grid grid = MakeGrid(cells, 3, 3, 12, step: 0.2f);

        var r = TopologyCrossChecks.EstimateAxialTortuosity(grid, nWalkers: 20, seed: 7);

        Assert.True(r.Successes > 0, "no walk converged — widened open tunnel should be trivial");
        Assert.NotNull(r.MeanTortuosity);
        Assert.True(r.MeanTortuosity >= 1.0 - 1e-9, $"mean={r.MeanTortuosity} < 1.0 is not physically possible");
    }

    [Fact]
    public void Tortuosity_Converges_On_The_Real_Shipped_Pine_Anchor_Cem()
    {
        // Regression pin: the FIRST version of the forward bias (any non-increasing k-distance move
        // counted as "forward", including pure lateral wandering) trapped every single walker on this
        // exact 88×88×320 grid — 0/100 attempts converged, despite 100% open porosity and full
        // percolation. That is the real cem/anchor_zone1.pine.json shape, not a synthetic worst case.
        AnchorCem cem = new()
        {
            OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, BusRodDiameterMm = 1.0f, LengthMm = 40f,
            GyroidPeriodMm = 2.5f, GyroidPeriodRimMm = 2.0f, GyroidWallParam = 1.0f,
        };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem);
        var r = TopologyCrossChecks.EstimateAxialTortuosity(grid, nWalkers: 10, seed: 1);

        Assert.True(r.Successes >= 8, $"only {r.Successes}/10 walkers converged ({r.Attempts} attempts) — the labyrinth-trap regression may be back");
        Assert.True(r.MeanTortuosity is > 1.0 and < 3.0, $"mean={r.MeanTortuosity} outside a physically sane gyroid-labyrinth range");
    }

    [Fact]
    public void Tortuosity_Is_Inconclusive_On_A_Grid_With_No_Pore()
    {
        Connectivity.Grid grid = MakeGrid([Phase.Solid, Phase.Solid], 1, 1, 2);
        var r = TopologyCrossChecks.EstimateAxialTortuosity(grid, nWalkers: 5);

        Assert.Equal(0, r.Successes);
        Assert.Null(r.MeanTortuosity);
    }

    // --- As-printed: the morphological opening at the SLM wall floor ---

    [Fact]
    public void Print_Fidelity_Agrees_For_A_Wall_Comfortably_Above_The_Slm_Floor()
    {
        // period 2.5 mm, default wallParam 1.0 ⇒ wall well above the 0.2 mm SLM floor (canon: wall ≈
        // 0.1·period ≈ 0.25 mm) — the opening must take almost nothing and leave the topology intact.
        AnchorCem cem = new() { OuterDiameterMm = 6f, BoreDiameterMm = 1.0f, LengthMm = 6f, GyroidPeriodMm = 2.5f };
        var r = TopologyCrossChecks.CheckPrintFidelity(Zone1Anode.Gyroid(cem), cem);

        Assert.Equal(0.05f, r.StepMm);                              // min(2.5/24, 0.2/4)
        Assert.Equal(TopologyCrossChecks.SlmMinWallMm, r.FloorMm);
        Assert.True(r.Intent.PorePercolates[2], "intent sample must percolate axially");
        Assert.True(r.AsPrinted.PorePercolates[2], "as-printed sample must percolate axially");
        Assert.True(r.TopologyMatches, $"intent clusters={r.Intent.PoreClusterCount} vs as-printed clusters={r.AsPrinted.PoreClusterCount}");

        // MEASURED 2026-09-10: 0.00727. The band is ±~35 % around that measurement, not a round guess —
        // wide enough to absorb a 1-ULP float-trig difference between the macOS ARM64 dev box and the
        // Linux x64 CI runner flipping a handful of boundary cells, tight enough that a broken erosion
        // (which takes tens of percent — see the shipped-SKU pin below) reds it immediately.
        Assert.InRange(r.SubFloorSolidFraction, 0.005, 0.010);
    }

    [Fact]
    public void Opening_Deletes_A_Sub_Floor_Wall_And_Keeps_A_Slab_Thicker_Than_The_Ball()
    {
        // Ball radius 0.2 mm on a 0.1 mm grid ⇒ r = 2 cells, so the opening keeps a slab only at
        // ≥ 2r+1 = 5 cells. That quantisation IS the declared ceiling of the model (whole cells, ±1),
        // so all three cases are pinned: 1 cell and 2r cells go, 2r+1 cells survives untouched.
        const float fStep = 0.1f, fRadius = 0.2f;

        (Connectivity.Grid one, double dSubOne) = TopologyCrossChecks.OpenSolid(SlabGrid(5, 5), fRadius);
        Assert.Equal(0, CountSolid(one));
        Assert.Equal(1.0, dSubOne, 9);

        (Connectivity.Grid four, double dSubFour) = TopologyCrossChecks.OpenSolid(SlabGrid(3, 6), fRadius);   // 4 layers = 2r
        Assert.Equal(0, CountSolid(four));
        Assert.Equal(1.0, dSubFour, 9);

        (Connectivity.Grid five, double dSubFive) = TopologyCrossChecks.OpenSolid(SlabGrid(3, 7), fRadius);
        Assert.Equal(5 * 5 * 5, CountSolid(five));   // 5 solid layers × the full 5×5 cross-section
        Assert.Equal(0.0, dSubFive, 9);

        // An 11×5×5 pore box with the X-layers [iLo, iHi] made Solid.
        static Connectivity.Grid SlabGrid(int iLo, int iHi)
        {
            const int nx = 11, ny = 5, nz = 5;
            var cells = new Phase[nx * ny * nz];
            Array.Fill(cells, Phase.Pore);
            for (int i = iLo; i <= iHi; i++)
                for (int j = 0; j < ny; j++)
                    for (int k = 0; k < nz; k++)
                        cells[(((i * ny) + j) * nz) + k] = Phase.Solid;
            return new Connectivity.Grid(cells, nx, ny, nz, fStep);
        }

        static int CountSolid(Connectivity.Grid g)
        {
            int n = 0;
            foreach (Phase p in g.Cells) if (p == Phase.Solid) n++;
            return n;
        }
    }

    // What is pinned here is an ORDERING the physics predicts, never a threshold: in a radially graded
    // sheet gyroid the RIM cell is the finest, so the rim wall (≈ rim period / 10, 01_01 §5.5) is the
    // thinnest metal in the part, and the share the print floor deletes must fall monotonically as that
    // rim wall grows. Measured 2026-09-10 (grid 0.050 mm, floor 200 µm): stepped (rim 1.3 mm ⇒ wall
    // ≈0.13, BELOW the floor) 71.8 % > broadleaf (1.6 ⇒ 0.16, below) 49.7 % > pine (2.0) 24.4 % >
    // mangrove (2.2) 20.5 % > oak (2.8 ⇒ 0.28, well above) 4.3 % > tropical (3.2 ⇒ 0.32) 1.5 %.
    // graded_porosity is EXCLUDED by construction, not by hand: its wall BAND is graded too (1.3 → 0.8),
    // so the rim period alone does not predict where it lands (measured 12.5 %, between mangrove and
    // oak) — the filter below drops exactly the SKUs whose porosity axis moves.
    [Fact]
    public void As_Printed_Sub_Floor_Share_Falls_As_The_Rim_Wall_Thickens_On_The_Shipped_Cems()
    {
        var aByRim = CemFixtures.AnchorFiles()
            .Select(CemFixtures.Anchor)
            .Where(cem => cem.GyroidWallParamRim <= 0f)          // constant porosity band ⇒ rim PERIOD is the only wall axis
            .OrderBy(CemFixtures.RimPeriodMm)
            .ToArray();
        Assert.True(aByRim.Length >= 5, $"only {aByRim.Length} constant-band anchor SKUs found — the chain below would be near-vacuous");

        var aSubFloor = aByRim
            .Select(cem => TopologyCrossChecks.CheckPrintFidelity(Zone1Anode.Gyroid(cem), cem).SubFloorSolidFraction)
            .ToArray();

        int nCompared = 0;
        for (int i = 1; i < aByRim.Length; i++)
        {
            if (CemFixtures.RimPeriodMm(aByRim[i]) <= CemFixtures.RimPeriodMm(aByRim[i - 1])) continue; // equal rim ⇒ no prediction
            nCompared++;
            Assert.True(aSubFloor[i - 1] > aSubFloor[i],
                $"{aByRim[i - 1].Name} (rim {CemFixtures.RimPeriodMm(aByRim[i - 1]):F1} mm) lost {aSubFloor[i - 1]:P1} to the print floor " +
                $"but {aByRim[i].Name} (rim {CemFixtures.RimPeriodMm(aByRim[i]):F1} mm) lost {aSubFloor[i]:P1} — a THINNER rim wall must lose MORE");
        }
        Assert.True(nCompared >= 4, $"only {nCompared} ordered pairs compared — the chain proved almost nothing");
    }
}
