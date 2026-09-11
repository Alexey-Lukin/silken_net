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

    // ── 3. As-printed model: morphological OPENING of the solid at the SLM wall floor ──────────
    //
    // MODEL. The canon-sourced minimum printable wall for SLM Ti-6Al-4V is ~200 µm (01_01 §5.5 /
    // 01_02 §6: "SLM стінка ~200 µm … мін. друкована пора ≈1.2 мм"), independent of and coarser than the
    // 30 µm Z-layer (01_02 §6 "SLM: шар 30 µm" — that governs build-direction slicing, not the XY
    // feature floor a thin gyroid wall must clear). A feature the machine cannot hold is not COARSENED,
    // it is ABSENT. So the as-printed solid is the morphological OPENING of the intent solid by a
    // Euclidean ball of radius floor/2: erode (a solid cell survives only if the whole ball around it is
    // solid — Outside counts as solid, so the part's own envelope surface is not eaten and only Pore
    // erodes), then dilate the survivors back, but only onto cells that were solid to begin with. What
    // the opening deletes is exactly the sub-floor material — wall thinner than the melt track can hold
    // — and SubFloorSolidFraction is that deleted share. Both halves are measured on ONE grid, sampled
    // at min(intent step, floor/4), so the ball is ≥2 cells in radius and the floor itself is resolved.
    //
    // MEASURED GROUND (2026-09-10, the seven shipped cem/anchor_zone1.*.json). A coarse RESAMPLE cannot
    // model a print floor, in either direction. Sampled at the 0.2 mm floor, EVERY SKU "fails": pore
    // clusters collapse to 1 everywhere and solid-disconnected reads broadleaf 10.6 % · stepped 52 % ·
    // pine 3.5 % · mangrove 2.9 % · graded_porosity 2.2 % · oak 0.3 % · tropical 0.06 % — that is lattice
    // aliasing of a curved wall against a cubic grid, not manufacturability. And a resample is a
    // RESOLUTION knob, not a physics one, so it can equally land FINER than the intent grid, in which
    // case the diff reports the intent grid's own under-resolution under a manufacturability caption, or
    // land on exactly the intent step and match vacuously. An opening has no such freedom: the ball
    // radius is the physical floor, and refining the grid only sharpens the same verdict.
    //
    // CEILING (declared, not hidden). An opening on a cubic grid quantises thickness to whole cells, so
    // it over-/under-estimates a wall by up to one cell (at floor/4 sampling, ±50 µm on a 200 µm floor);
    // a slab survives at ≥2r+1 cells, i.e. 0.25 mm at the shipped step, not 0.20 mm exactly. It models
    // the XY feature floor ONLY: not build-direction slicing (30 µm layers, staircase on shallow
    // overhangs), not support/overhang collapse, not powder trapping or de-powdering of the surviving
    // channels — those are 01_02 §1.3 bench questions, and nothing here substitutes for them.
    // ⚖️ RATIFIED 2026-09-10 (founder, 00_07 HW.33): this number is a VENDOR INPUT — every machine and
    // powder has its own min wall — so canon must not hardcode one supplier's machine. It stays here as
    // the CANON DEFAULT (01_01 §5.5) for a manifest that declares nothing, and `AnchorCem.SlmMinWallMm`
    // overrides it per part once an RFQ answers. ⚠️ Read `FloorSourceMm` below, not this constant, in
    // anything that reports a measurement: quoting the default while a manifest overrode it is the exact
    // shape of a report that describes the instrument instead of the tree.
    public const float CanonSlmMinWallMm = 0.2f;

    // The floor actually in force for this part: the manifest's vendor number, else the canon default.
    public static float FloorMmFor(AnchorCem cem) => cem.SlmMinWallMm ?? CanonSlmMinWallMm;

    // The one grid both halves of the as-printed model are measured on. One home — the report line
    // prints this number and must not re-derive the formula. NB the floor/4 branch wins for every
    // possible AnchorCem at the canon floor, because AdaptiveStepMm clamps at 0.06 mm > 0.05; the Min is
    // the guard that keeps the as-printed grid from ever being COARSER than the intent one if either
    // bound moves. 🔴 **The floor sets the GRID as well as the threshold, and that is the half a reader
    // loses**: a vendor floor of 0.1 instead of 0.2 halves the step on EVERY axis, i.e. ~8× the cells and
    // roughly an order of magnitude more time per run. A cheaper-sounding machine is not a cheaper run.
    public static float PrintGridStepMm(AnchorCem cem)
        => MathF.Min(Connectivity.AdaptiveStepMm(cem), FloorMmFor(cem) / 4f);

    internal sealed record PrintFidelityResult
    {
        public required ConnectivityMetrics Intent { get; init; }
        public required ConnectivityMetrics AsPrinted { get; init; }

        // ⚠ A topology-CLASS comparison, and therefore blind to HOW MUCH metal the floor deleted: a SKU
        // that is already single-labyrinth matches trivially. Measured 2026-09-10 on the shipped seven —
        // `stepped` reads ✓ (1→1) while losing 71.8 % of its solid, the worst of the family; the six
        // sheet SKUs read ⚠ (2→1) losing 1.5–49.7 %. Never read this flag without SubFloorSolidFraction.
        public required bool TopologyMatches { get; init; }
        public required float StepMm { get; init; }              // sampling step of BOTH metrics above
        public required float FloorMm { get; init; }             // the modelled print floor in force (manifest vendor input, else canon)
        public required double SubFloorSolidFraction { get; init; } // solid removed by the opening / intent solid, 0..1
    }

    public static PrintFidelityResult CheckPrintFidelity(IImplicit sdf, AnchorCem cem)
    {
        float fStep = PrintGridStepMm(cem);
        Connectivity.Grid gridIntent = Connectivity.SampleAnchor(sdf, cem, fStep);
        ConnectivityMetrics mIntent = Connectivity.Analyse(gridIntent);

        (Connectivity.Grid gridPrinted, double dSubFloor) = OpenSolid(gridIntent, FloorMmFor(cem) / 2f);
        ConnectivityMetrics mPrinted = Connectivity.Analyse(gridPrinted);

        bool bMatches = mIntent.PoreClusterCount == mPrinted.PoreClusterCount
            && mIntent.PorePercolates.SequenceEqual(mPrinted.PorePercolates);
        return new PrintFidelityResult
        {
            Intent = mIntent,
            AsPrinted = mPrinted,
            TopologyMatches = bMatches,
            StepMm = fStep,
            FloorMm = FloorMmFor(cem),
            SubFloorSolidFraction = dSubFloor,
        };
    }

    // Morphological opening of the Solid phase by a ball of radius fRadiusMm (r = radius/step cells,
    // ≥1). Returns the opened grid — sub-floor solid demoted to Pore, Outside untouched — and the
    // removed share of the original solid. Explicit precomputed offset stencil (dx²+dy²+dz² ≤ r²), no
    // recursion, no LINQ in the loops: O(N·|stencil|), |stencil| = 33 at r = 2.
    internal static (Connectivity.Grid Opened, double SubFloorSolidFraction) OpenSolid(
        Connectivity.Grid grid, float fRadiusMm)
    {
        Phase[] aIn = grid.Cells;
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        int nR = Math.Max(1, (int)MathF.Round(fRadiusMm / grid.StepMm));
        int nR2 = nR * nR;

        int nStencil = 0;
        for (int di = -nR; di <= nR; di++)
            for (int dj = -nR; dj <= nR; dj++)
                for (int dk = -nR; dk <= nR; dk++)
                    if ((di * di) + (dj * dj) + (dk * dk) <= nR2) nStencil++;

        var aDi = new int[nStencil];
        var aDj = new int[nStencil];
        var aDk = new int[nStencil];
        var aFlat = new int[nStencil];
        int t = 0;
        for (int di = -nR; di <= nR; di++)
            for (int dj = -nR; dj <= nR; dj++)
                for (int dk = -nR; dk <= nR; dk++)
                {
                    if ((di * di) + (dj * dj) + (dk * dk) > nR2) continue;
                    aDi[t] = di; aDj[t] = dj; aDk[t] = dk;
                    aFlat[t] = (((di * ny) + dj) * nz) + dk;
                    t++;
                }

        // Erosion. A solid cell is CORE iff no Pore cell lies within the ball. Off-grid neighbours are
        // Outside by construction (the sample box only ever extends past the envelope), and Outside
        // counts as solid — the envelope skin must not erode, only genuinely thin wall must.
        var aCore = new bool[aIn.Length];
        long nSolid = 0;
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                {
                    int idx = (((i * ny) + j) * nz) + k;
                    if (aIn[idx] != Phase.Solid) continue;
                    nSolid++;
                    bool bCore = true;
                    for (int s = 0; s < nStencil; s++)
                    {
                        int ii = i + aDi[s]; if (ii < 0 || ii >= nx) continue;
                        int jj = j + aDj[s]; if (jj < 0 || jj >= ny) continue;
                        int kk = k + aDk[s]; if (kk < 0 || kk >= nz) continue;
                        if (aIn[idx + aFlat[s]] == Phase.Pore) { bCore = false; break; }
                    }
                    aCore[idx] = bCore;
                }

        // Dilation, clipped to the original solid: every cell in the ball of a core cell that WAS solid
        // comes back. Everything else that was solid stays demoted — that is the sub-floor material.
        var aOut = new Phase[aIn.Length];
        for (int c = 0; c < aIn.Length; c++)
            aOut[c] = aIn[c] == Phase.Solid ? Phase.Pore : aIn[c];

        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                {
                    int idx = (((i * ny) + j) * nz) + k;
                    if (!aCore[idx]) continue;
                    for (int s = 0; s < nStencil; s++)
                    {
                        int ii = i + aDi[s]; if (ii < 0 || ii >= nx) continue;
                        int jj = j + aDj[s]; if (jj < 0 || jj >= ny) continue;
                        int kk = k + aDk[s]; if (kk < 0 || kk >= nz) continue;
                        int to = idx + aFlat[s];
                        if (aIn[to] == Phase.Solid) aOut[to] = Phase.Solid;
                    }
                }

        long nKept = 0;
        foreach (Phase p in aOut) if (p == Phase.Solid) nKept++;

        return (grid with { Cells = aOut }, nSolid > 0 ? (double)(nSolid - nKept) / nSolid : 0.0);
    }
}
