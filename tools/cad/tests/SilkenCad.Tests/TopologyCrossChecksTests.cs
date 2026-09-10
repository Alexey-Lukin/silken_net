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

    // --- Print fidelity: a comfortably-thick-walled small anchor should read the same both ways ---

    [Fact]
    public void Print_Fidelity_Agrees_For_A_Wall_Comfortably_Above_The_Slm_Floor()
    {
        // period 2.5 mm, default wallParam 1.0 ⇒ wall well above the 0.2 mm SLM floor (canon: wall ≈
        // 0.1·period ≈ 0.25 mm) — both resolutions should see the SAME topology class.
        AnchorCem cem = new() { OuterDiameterMm = 6f, BoreDiameterMm = 1.0f, LengthMm = 6f, GyroidPeriodMm = 2.5f };
        var r = TopologyCrossChecks.CheckPrintFidelity(Zone1Anode.Gyroid(cem), cem);

        Assert.True(r.Intent.PorePercolates[2], "intent-resolution sample must percolate axially");
        Assert.True(r.AsPrinted.PorePercolates[2], "as-printed-resolution sample must percolate axially");
        Assert.True(r.TopologyMatches, $"intent clusters={r.Intent.PoreClusterCount} vs as-printed clusters={r.AsPrinted.PoreClusterCount}");
    }
}
