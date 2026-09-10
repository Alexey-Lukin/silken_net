// SPDX-License-Identifier: AGPL-3.0-or-later
using PicoGK;

namespace SilkenCad;

// ARCH.25 nice-to-have residual: three checks that go BEYOND the shipped flood-fill audit
// (Connectivity.cs) — an independent topological invariant to catch a bug in the flood-fill itself,
// a transport-relevant number the flood-fill doesn't produce, and a manufacturability resample the
// flood-fill's SDF-intent sampling deliberately does not attempt. All three CONSUME a Connectivity.Grid
// (or resample via Connectivity.SampleAnchor) — no duplicated sampling logic, no new SDF math.
internal static class TopologyCrossChecks
{
    // ── 1. Euler characteristic cross-check ────────────────────────────────────────────────────
    //
    // χ = V − E + F − C of the SOLID phase, treated as a cubical complex (each solid voxel = a closed
    // unit cube glued to its neighbours along shared faces/edges/vertices — the standard digital-
    // topology definition). Computed by direct grid-position iteration: a vertex/edge/face is
    // "occupied" iff at least one adjacent solid voxel touches it. No hashing, no mesh, no genus
    // formula borrowed from a paper — just inclusion-exclusion over the lattice, which is exactly what
    // makes it independently trustworthy as a CROSS-check against the flood-fill.
    //
    // For a compact region embedded in R³ (boundary present ⇒ b3 = 0), Euler–Poincaré gives
    // χ = b0 − b1 + b2, where b0 = connected components, b1 = independent tunnels/handles (genus-like),
    // b2 = enclosed cavities. The flood-fill ALREADY measures b0 (solid cluster count) and b2 (pore
    // clusters that never touch a domain surface — an enclosed void is topologically a cavity of the
    // solid). So instead of comparing χ to a borrowed TPMS-genus number, solve the SAME equation for
    // the one quantity neither check has produced yet: b1 = b0 + b2 − χ. b1 is an independent-tunnel
    // COUNT and must be a non-negative integer; if it comes out negative, that is proof one of the two
    // independent measurements (flood-fill or Euler-χ) has a bug — exactly the brief's "treat
    // disagreement as a bug in one of the two checks, not a new physical finding."
    internal sealed record EulerCrossCheckResult
    {
        public required long EulerCharacteristic { get; init; }
        public required int Components { get; init; }   // b0 (flood-fill solid clusters)
        public required int Cavities { get; init; }      // b2 (flood-fill enclosed/closed pore clusters)
        public required long Handles { get; init; }      // b1, derived: b0 + b2 − χ
        public required bool Sound { get; init; }        // b1 ≥ 0 — false ⇒ one of the two checks is wrong
    }

    // `floodFill` must be Connectivity.Analyse(grid) on the SAME grid — b0/b2 come from its already-
    // computed cluster lists (SolidClusterCount/ClosedPoreClusterCount), so this never re-walks the field.
    public static EulerCrossCheckResult EulerCrossCheck(Connectivity.Grid grid, ConnectivityMetrics floodFill)
    {
        long chi = EulerCharacteristicSolid(grid);
        long handles = floodFill.SolidClusterCount + floodFill.ClosedPoreClusterCount - chi;
        return new EulerCrossCheckResult
        {
            EulerCharacteristic = chi,
            Components = floodFill.SolidClusterCount,
            Cavities = floodFill.ClosedPoreClusterCount,
            Handles = handles,
            Sound = handles >= 0,
        };
    }

    private static long EulerCharacteristicSolid(Connectivity.Grid grid)
    {
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        bool Solid(int i, int j, int k) =>
            i >= 0 && i < nx && j >= 0 && j < ny && k >= 0 && k < nz &&
            grid.Cells[grid.Index(i, j, k)] == Phase.Solid;

        long nVertices = 0;
        for (int i = 0; i <= nx; i++)
            for (int j = 0; j <= ny; j++)
                for (int k = 0; k <= nz; k++)
                {
                    bool bTouched = false;
                    for (int di = -1; di <= 0 && !bTouched; di++)
                        for (int dj = -1; dj <= 0 && !bTouched; dj++)
                            for (int dk = -1; dk <= 0 && !bTouched; dk++)
                                if (Solid(i + di, j + dj, k + dk)) bTouched = true;
                    if (bTouched) nVertices++;
                }

        long nEdges = 0;
        // X-edges: span (i,j,k)-(i+1,j,k); touched by voxels at x=i, y∈{j-1,j}, z∈{k-1,k}.
        for (int i = 0; i < nx; i++)
            for (int j = 0; j <= ny; j++)
                for (int k = 0; k <= nz; k++)
                    if (Solid(i, j - 1, k - 1) || Solid(i, j - 1, k) || Solid(i, j, k - 1) || Solid(i, j, k)) nEdges++;
        // Y-edges: span (i,j,k)-(i,j+1,k); touched by voxels at x∈{i-1,i}, y=j, z∈{k-1,k}.
        for (int i = 0; i <= nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k <= nz; k++)
                    if (Solid(i - 1, j, k - 1) || Solid(i - 1, j, k) || Solid(i, j, k - 1) || Solid(i, j, k)) nEdges++;
        // Z-edges: span (i,j,k)-(i,j,k+1); touched by voxels at x∈{i-1,i}, y∈{j-1,j}, z=k.
        for (int i = 0; i <= nx; i++)
            for (int j = 0; j <= ny; j++)
                for (int k = 0; k < nz; k++)
                    if (Solid(i - 1, j - 1, k) || Solid(i - 1, j, k) || Solid(i, j - 1, k) || Solid(i, j, k)) nEdges++;

        long nFaces = 0;
        // XY-faces (fixed k): touched by voxels at z∈{k-1,k}.
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k <= nz; k++)
                    if (Solid(i, j, k - 1) || Solid(i, j, k)) nFaces++;
        // YZ-faces (fixed i): touched by voxels at x∈{i-1,i}.
        for (int i = 0; i <= nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                    if (Solid(i - 1, j, k) || Solid(i, j, k)) nFaces++;
        // XZ-faces (fixed j): touched by voxels at y∈{j-1,j}.
        for (int i = 0; i < nx; i++)
            for (int j = 0; j <= ny; j++)
                for (int k = 0; k < nz; k++)
                    if (Solid(i, j - 1, k) || Solid(i, j, k)) nFaces++;

        long nCubes = 0;
        foreach (Phase p in grid.Cells) if (p == Phase.Solid) nCubes++;

        return nVertices - nEdges + nFaces - nCubes;
    }

    // ── 2. Tortuosity via random walk on the percolated pore cluster ──────────────────────────
    //
    // A self-avoiding, three-tier forward-biased random walk from the low-Z face to the high-Z face,
    // through Pore-phase voxels only. Path length = steps × StepMm (6-connectivity ⇒ every step is
    // exactly one axis-aligned voxel edge); displacement = the Euclidean distance between the actual
    // start and end voxel CENTRES (not the bbox span — a walk that drifts laterally ends somewhere
    // other than straight across). τ = path / displacement, the standard geometric-tortuosity
    // definition. Self-avoidance (never revisit a voxel within ONE walk) is what guarantees
    // termination on a finite connected graph without literally replicating an unconstrained 3-D
    // random walk's pathological hitting times; the bias (see OneWalk — ADVANCING preferred over
    // LATERAL preferred over forced RETREAT, each tier still a uniform-random pick) keeps the walk
    // converging within a generous step budget while every step stays genuinely stochastic — it is
    // NOT a shortest-path / BFS search, and a walk that boxes itself in is abandoned and retried from
    // a fresh random start rather than silently reporting a number for a failed attempt. A single-tier
    // "non-retreating" bias treated pure lateral wandering as equal to real progress and trapped every
    // walker on the real shipped pine anchor CEM (0/100 — see the regression test); measure before
    // trusting a walk-convergence rate, don't assume a bias scheme works from its description alone.
    internal sealed record TortuosityResult
    {
        // null (never NaN — "не виміряно" stays a sentinel, not a fabricated number, and NaN is not
        // even valid JSON) when zero walks converged.
        public required double? MeanTortuosity { get; init; }
        public required double? MinTortuosity { get; init; }
        public required double? MaxTortuosity { get; init; }
        public required int Successes { get; init; }
        public required int Attempts { get; init; }
    }

    public static TortuosityResult EstimateAxialTortuosity(
        Connectivity.Grid grid, int nWalkers = 30, int nStepBudgetFactor = 25, int? seed = null)
    {
        var (kLo, kHi) = InsideZRange(grid);
        if (kHi <= kLo) return Inconclusive();

        var starts = new List<int>();
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
            {
                int idx = grid.Index(i, j, kLo);
                if (grid.Cells[idx] == Phase.Pore) starts.Add(idx);
            }
        if (starts.Count == 0) return Inconclusive();

        Random rng = seed is { } s ? new Random(s) : new Random();
        int nStepBudget = Math.Max(1, (kHi - kLo + 1)) * nStepBudgetFactor;
        var aTau = new List<double>();
        int nAttempts = 0, nMaxAttempts = nWalkers * 10;

        while (aTau.Count < nWalkers && nAttempts < nMaxAttempts)
        {
            nAttempts++;
            int start = starts[rng.Next(starts.Count)];
            (int steps, int end)? walk = OneWalk(grid, start, kHi, nStepBudget, rng);
            if (walk is not { } w) continue;

            (int iS, int jS, int kS) = Decompose(grid, start);
            (int iE, int jE, int kE) = Decompose(grid, w.end);
            double dx = (iE - iS) * grid.StepMm, dy = (jE - jS) * grid.StepMm, dz = (kE - kS) * grid.StepMm;
            double dDisplMm = Math.Sqrt((dx * dx) + (dy * dy) + (dz * dz));
            if (dDisplMm < 1e-9) continue; // degenerate (shouldn't happen once k advances) — retry

            double dPathMm = w.steps * (double)grid.StepMm;
            aTau.Add(dPathMm / dDisplMm);
        }

        if (aTau.Count == 0) return Inconclusive() with { Attempts = nAttempts };
        return new TortuosityResult
        {
            MeanTortuosity = aTau.Average(),
            MinTortuosity = aTau.Min(),
            MaxTortuosity = aTau.Max(),
            Successes = aTau.Count,
            Attempts = nAttempts,
        };

        static TortuosityResult Inconclusive() => new()
        { MeanTortuosity = null, MinTortuosity = null, MaxTortuosity = null, Successes = 0, Attempts = 0 };
    }

    private static (int steps, int end)? OneWalk(Connectivity.Grid grid, int start, int kTarget, int nStepBudget, Random rng)
    {
        var visited = new HashSet<int> { start };
        int cur = start;
        var buf = new List<int>(6);

        for (int steps = 0; steps < nStepBudget; steps++)
        {
            (int i, int j, int k) = Decompose(grid, cur);
            if (k == kTarget) return (steps, cur);

            buf.Clear();
            AddIfPoreUnvisited(grid, visited, buf, i - 1, j, k);
            AddIfPoreUnvisited(grid, visited, buf, i + 1, j, k);
            AddIfPoreUnvisited(grid, visited, buf, i, j - 1, k);
            AddIfPoreUnvisited(grid, visited, buf, i, j + 1, k);
            AddIfPoreUnvisited(grid, visited, buf, i, j, k - 1);
            AddIfPoreUnvisited(grid, visited, buf, i, j, k + 1);
            if (buf.Count == 0) return null; // self-avoiding dead end — caller retries from a fresh start

            // Three-tier bias, re-evaluated every step (not just the first): ADVANCING (strictly closer
            // to the target face) preferred 80% of the time when available, else LATERAL (same
            // k-distance — a detour around an obstacle) preferred 70% of the time when available, else
            // whatever is left (a forced retreat). A gyroid's pore space is a genuine 3-D labyrinth with
            // heavy local branching (that IS what the Euler-χ handle-count above measures) — a walk that
            // treats lateral wandering as equally "forward" as real Z-progress can spend its ENTIRE
            // self-avoidance budget circling in one k-plane and trap itself with the target still hundreds
            // of steps away (measured: 0/100 on the real pine anchor CEM before this fix). Tiering by
            // STRICT distance-reduction is what actually keeps the walk marching.
            int dCurDist = Math.Abs(kTarget - k);
            var advancing = buf.Where(idx => Math.Abs(kTarget - Decompose(grid, idx).k) < dCurDist).ToList();
            var nonRetreating = buf.Where(idx => Math.Abs(kTarget - Decompose(grid, idx).k) <= dCurDist).ToList();
            List<int> pool =
                advancing.Count > 0 && rng.NextDouble() < 0.80 ? advancing :
                nonRetreating.Count > 0 && rng.NextDouble() < 0.70 ? nonRetreating :
                buf;
            int next = pool[rng.Next(pool.Count)];
            visited.Add(next);
            cur = next;
        }
        return null; // ran out of budget — inconclusive, caller retries
    }

    // CHECKS only — must not mutate `visited`. Only the neighbour actually STEPPED to becomes visited
    // (in OneWalk, after the random pick); marking every OFFERED candidate would make the walk far
    // more self-avoiding than intended and bias tortuosity upward for no physical reason.
    private static void AddIfPoreUnvisited(Connectivity.Grid grid, HashSet<int> visited, List<int> buf, int i, int j, int k)
    {
        if (i < 0 || i >= grid.Nx || j < 0 || j >= grid.Ny || k < 0 || k >= grid.Nz) return;
        int idx = grid.Index(i, j, k);
        if (grid.Cells[idx] != Phase.Pore) return;
        if (visited.Contains(idx)) return;
        buf.Add(idx);
    }

    private static (int i, int j, int k) Decompose(Connectivity.Grid grid, int idx)
        => (idx / (grid.Ny * grid.Nz), (idx / grid.Nz) % grid.Ny, idx % grid.Nz);

    private static (int kLo, int kHi) InsideZRange(Connectivity.Grid grid)
    {
        int kLo = grid.Nz, kHi = -1;
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
                for (int k = 0; k < grid.Nz; k++)
                    if (grid.Cells[grid.Index(i, j, k)] != Phase.Outside)
                    {
                        if (k < kLo) kLo = k;
                        if (k > kHi) kHi = k;
                    }
        return (kLo, kHi);
    }

    // ── 3. Voxel-cross-check on the as-printed grid (manufacturability, not SDF-intent) ────────
    //
    // Connectivity.SampleAnchor's adaptive step (period/16, floor 0.06 mm) is a SIMULATION-fidelity
    // choice: fine enough to resolve whatever wall the CAD file specifies, however thin. It says
    // nothing about what SLM Ti-6Al-4V can actually BUILD — the real, canon-sourced minimum
    // printable wall is ~200 µm (01_01 §5.5 / 01_02 §6: "SLM стінка ~200 µm … мін. друкована пора
    // ≈1.2 мм"), independent of and coarser than the 30 µm Z-layer thickness (01_02 §6 "SLM: шар
    // 30 µm" — that number governs build-direction slicing, not the XY feature floor a thin gyroid
    // wall must clear). This resamples the SAME SDF at a step tied to that print floor (wall must
    // span ≳2 voxels, the same rule SampleAnchor already applies to the design period) and diffs
    // topology against the intent-resolution sample. The two are NOT always ordered — for a coarse
    // design period the print-floor step is finer (this becomes a resolution-convergence sanity
    // check); for a design pushed toward the anatomical 100 µm rim floor 01_01 §5.5 already flags as
    // SLM-incompatible, the print-floor step is the coarser, binding one, and THIS is where a design
    // that looks sound in SDF-intent space would show real degradation once printed.
    public const float SlmMinWallMm = 0.2f;

    internal sealed record PrintFidelityResult
    {
        public required ConnectivityMetrics Intent { get; init; }
        public required ConnectivityMetrics AsPrinted { get; init; }
        public required bool TopologyMatches { get; init; }
    }

    public static PrintFidelityResult CheckPrintFidelity(IImplicit sdf, AnchorCem cem)
    {
        Connectivity.Grid gridIntent = Connectivity.SampleAnchor(sdf, cem);
        Connectivity.Grid gridPrinted = Connectivity.SampleAnchor(sdf, cem, SlmMinWallMm / 2f);
        ConnectivityMetrics mIntent = Connectivity.Analyse(gridIntent);
        ConnectivityMetrics mPrinted = Connectivity.Analyse(gridPrinted);
        bool bMatches = mIntent.PoreClusterCount == mPrinted.PoreClusterCount
            && mIntent.PorePercolates.SequenceEqual(mPrinted.PorePercolates);
        return new PrintFidelityResult { Intent = mIntent, AsPrinted = mPrinted, TopologyMatches = bMatches };
    }
}
