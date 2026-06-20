using System.Numerics;
using PicoGK;

namespace SilkenCad;

// Two-phase topological audit of the gyroid anode (ARCH.25). We sample the CEM's own SDF on a
// regular grid into a 3-phase field {Outside, Solid, Pore} and flood-fill it (6-connectivity,
// the conservative Hoshen-Kopelman standard for pore networks). One audit predicts FOUR physical
// gates that the canon otherwise needs separate lab tests for:
//   • open-pore fraction   → Archimedes open porosity      (01_02 §1.2)
//   • pore percolation     → µCT connectivity + EAAE forced-flow through-channel (01_02 §1.3; a
//                            closed channel ⇒ H₂ gas-lock, the 01_02 §1.3a Failure-Mode-B defect)
//   • solid-disconnected   → AM floating-island / trapped-powder QC + anode electrical continuity
//                            (electrons travel the metal to the bus, 01_01 §1)
//   • closed-pore fraction → trapped-powder dead-end caverns (01_02 §1.3 vacuum-decant)
// Pure-managed: topology is a property of the FIELD, not the render — so this runs as a fast,
// display-less xUnit gate (no PicoGK Library.Go), and is stable to coarsening (a percolation
// threshold survives a coarser voxel better than an absolute volume does). It measures the
// geometric INTENT; an as-printed voxel cross-check is deferred. Sheet gyroid is TRICONTINUOUS
// (two pore labyrinths + one wall), so PoreClusterCount==2 for a sheet is a topology fact, NOT a
// defect — the gate must not punish it (HW.33 sheet-vs-network input).
internal enum Phase : byte { Outside = 0, Solid = 1, Pore = 2 }

internal sealed record ConnectivityMetrics
{
    public required double OpenPorosity { get; init; }              // pore reachable from any outer surface / total pore (computational Archimedes)
    public required double ClosedPoreFraction { get; init; }        // trapped voids = 1 − open
    public required double SolidDisconnectedFraction { get; init; } // metal NOT in the largest solid body (floating islands; print + electrical defect)
    public required bool[] PorePercolates { get; init; }            // [X, Y, Z] — a single pore cluster spanning the part (X,Y = rim-to-rim radial; Z = end-to-end axial)
    public required int PoreClusterCount { get; init; }             // big pore clusters (>2% vol): network→1, sheet→2 (tricontinuous)
}

internal static class Connectivity
{
    // Topology is a threshold property, so we sample COARSER than the 0.1 mm render — keeps
    // sweep×7 fast while staying stable. Override per call where finer resolution is wanted.
    public const float DefaultStepMm = 0.3f;
    private const double BigClusterFraction = 0.02; // a "big" cluster ≥ 2% of total phase voxels

    internal readonly record struct Grid(Phase[] Cells, int Nx, int Ny, int Nz, float StepMm)
    {
        public int Index(int i, int j, int k) => ((i * Ny) + j) * Nz + k;
    }

    // Anchor sampling: a cartesian box clipped to the pipe envelope (bore ≤ r ≤ outer). The gyroid
    // SDF is periodic, so the absolute Z origin only shifts the phase, never the topology/porosity.
    public static Grid SampleAnchor(IImplicit sdf, AnchorCem cem, float fStepMm = 0f)
    {
        float fROuter = cem.OuterDiameterMm / 2f;
        float fRInner = cem.BoreDiameterMm / 2f;
        // Adaptive resolution: the gyroid WALL is only ~period/10 thick, so the step must be tied to
        // the FINEST period — otherwise thin walls fall below the voxel and fragment into false solid
        // "islands" (the pore phase, ~10× coarser, is fine at any step). Wall must span ≳2 voxels.
        float fPeriodMin = cem.GyroidPeriodRimMm > 0f ? MathF.Min(cem.GyroidPeriodMm, cem.GyroidPeriodRimMm) : cem.GyroidPeriodMm;
        float fStep = fStepMm > 0f ? fStepMm : Math.Clamp(fPeriodMin / 16f, 0.06f, DefaultStepMm);
        return Sample(sdf, 2f * fROuter, 2f * fROuter, cem.LengthMm, fStep,
            (x, y, _) =>
            {
                float fR = MathF.Sqrt((x * x) + (y * y));
                return fR >= fRInner && fR <= fROuter; // inside the pipe wall
            },
            fXMin: -fROuter, fYMin: -fROuter, fZMin: 0f);
    }

    // Box sampling (no envelope) — the golden-test path: a plain gyroid cube with a known
    // topology (sheet → 2 pore labyrinths, network → 1), parity to the numeric experiment.
    public static Grid SampleBox(IImplicit sdf, float fExtentMm, float fStepMm = DefaultStepMm)
        => Sample(sdf, fExtentMm, fExtentMm, fExtentMm, fStepMm, static (_, _, _) => true, 0f, 0f, 0f);

    private static Grid Sample(
        IImplicit sdf, float fSizeX, float fSizeY, float fSizeZ, float fStepMm,
        Func<float, float, float, bool> fnInside, float fXMin, float fYMin, float fZMin)
    {
        int nx = Math.Max(1, (int)MathF.Ceiling(fSizeX / fStepMm));
        int ny = Math.Max(1, (int)MathF.Ceiling(fSizeY / fStepMm));
        int nz = Math.Max(1, (int)MathF.Ceiling(fSizeZ / fStepMm));
        var aCells = new Phase[nx * ny * nz];

        for (int i = 0; i < nx; i++)
        {
            float x = fXMin + ((i + 0.5f) * fStepMm);
            for (int j = 0; j < ny; j++)
            {
                float y = fYMin + ((j + 0.5f) * fStepMm);
                for (int k = 0; k < nz; k++)
                {
                    float z = fZMin + ((k + 0.5f) * fStepMm);
                    int idx = ((i * ny) + j) * nz + k;
                    if (!fnInside(x, y, z))
                    {
                        aCells[idx] = Phase.Outside;
                        continue;
                    }
                    // Solid where the SDF is negative (matches the render's BoolIntersect convention).
                    aCells[idx] = sdf.fSignedDistance(new Vector3(x, y, z)) < 0f ? Phase.Solid : Phase.Pore;
                }
            }
        }
        return new Grid(aCells, nx, ny, nz, fStepMm);
    }

    public static ConnectivityMetrics Analyse(in Grid grid)
    {
        // Inside extents per axis — used for percolation (a cluster spans the part if it touches
        // both the min and max INSIDE index, i.e. rim-to-rim for X/Y, end-to-end for Z).
        ExtentsInside(grid, out int iLo, out int iHi, out int jLo, out int jHi, out int kLo, out int kHi);

        var aPore = Components(grid, Phase.Pore);
        var aSolid = Components(grid, Phase.Solid);

        int nPoreTotal = aPore.Sum(c => c.Size);
        int nSolidTotal = aSolid.Sum(c => c.Size);

        // Open porosity: pore voxels in any surface-touching cluster / total pore (computational Archimedes).
        int nOpenPore = aPore.Where(c => c.TouchesSurface).Sum(c => c.Size);
        double dOpen = nPoreTotal > 0 ? (double)nOpenPore / nPoreTotal : 0.0;

        // Solid disconnected: metal not in the largest solid body (floating islands).
        int nLargestSolid = aSolid.Count > 0 ? aSolid.Max(c => c.Size) : 0;
        double dSolidDisc = nSolidTotal > 0 ? 1.0 - ((double)nLargestSolid / nSolidTotal) : 0.0;

        bool[] aPerc =
        [
            aPore.Any(c => c.ILo <= iLo && c.IHi >= iHi),
            aPore.Any(c => c.JLo <= jLo && c.JHi >= jHi),
            aPore.Any(c => c.KLo <= kLo && c.KHi >= kHi),
        ];

        int nBigPore = aPore.Count(c => nPoreTotal > 0 && (double)c.Size / nPoreTotal >= BigClusterFraction);

        return new ConnectivityMetrics
        {
            OpenPorosity = dOpen,
            ClosedPoreFraction = 1.0 - dOpen,
            SolidDisconnectedFraction = dSolidDisc,
            PorePercolates = aPerc,
            PoreClusterCount = nBigPore,
        };
    }

    // Per-bin porosity along the anchor axis. The v2 gradient is RADIAL, so this profile must be
    // ~FLAT — the axial-uniformity gate (complements the radial per-shell). Bins are ≥ ~2 gyroid
    // periods thick (fBinMm) so they AVERAGE OUT the cell-scale oscillation and reveal the true
    // axial TREND, not the within-period phase (a thin slice alternates wall↔void → false spread).
    public static double[] AxialProfile(in Grid grid, float fBinMm = 5.0f)
    {
        int nzPerBin = Math.Max(1, (int)MathF.Round(fBinMm / grid.StepMm));
        int nBins = Math.Max(1, grid.Nz / nzPerBin);
        var aPorosity = new double[nBins];
        for (int b = 0; b < nBins; b++)
        {
            int kLo = b * nzPerBin;
            int kHi = b == nBins - 1 ? grid.Nz : (b + 1) * nzPerBin;
            long nInside = 0, nPore = 0;
            for (int i = 0; i < grid.Nx; i++)
                for (int j = 0; j < grid.Ny; j++)
                    for (int k = kLo; k < kHi; k++)
                    {
                        Phase p = grid.Cells[grid.Index(i, j, k)];
                        if (p == Phase.Outside) continue;
                        nInside++;
                        if (p == Phase.Pore) nPore++;
                    }
            aPorosity[b] = nInside > 0 ? (double)nPore / nInside : 0.0;
        }
        return aPorosity;
    }

    // Global porosity of the sampled field: pore / (pore + solid), ignoring Outside. The render-free
    // companion to Voxels porosity — used by the wallParam scan (WallScan.cs) to map porosity vs wall band.
    public static double Porosity(in Grid grid)
    {
        long nPore = 0, nInside = 0;
        foreach (Phase p in grid.Cells)
        {
            if (p == Phase.Outside) continue;
            nInside++;
            if (p == Phase.Pore) nPore++;
        }
        return nInside > 0 ? (double)nPore / nInside : 0.0;
    }

    private readonly record struct Cluster(
        int Size, bool TouchesSurface,
        int ILo, int IHi, int JLo, int JHi, int KLo, int KHi);

    // Iterative 6-connected flood-fill over one phase. Each cluster records its size, whether it
    // touches a domain surface (an Outside neighbour or a bbox face — the Archimedes seed), and its
    // index bbox (for percolation spanning).
    private static List<Cluster> Components(in Grid grid, Phase phase)
    {
        Phase[] cells = grid.Cells;
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        var aSeen = new bool[cells.Length];
        var oClusters = new List<Cluster>();
        var oStack = new Stack<int>();

        for (int s = 0; s < cells.Length; s++)
        {
            if (cells[s] != phase || aSeen[s]) continue;

            aSeen[s] = true;
            oStack.Push(s);
            int nSize = 0;
            bool bSurface = false;
            int iLo = nx, iHi = -1, jLo = ny, jHi = -1, kLo = nz, kHi = -1;

            while (oStack.Count > 0)
            {
                int c = oStack.Pop();
                int i = c / (ny * nz);
                int j = (c / nz) % ny;
                int k = c % nz;
                nSize++;
                if (i < iLo) iLo = i; if (i > iHi) iHi = i;
                if (j < jLo) jLo = j; if (j > jHi) jHi = j;
                if (k < kLo) kLo = k; if (k > kHi) kHi = k;

                // Surface seed: on a bbox face, or adjacent to an Outside voxel (rim/bore wall).
                if (i == 0 || i == nx - 1 || j == 0 || j == ny - 1 || k == 0 || k == nz - 1)
                    bSurface = true;

                PushNeighbour(c, i > 0 ? c - (ny * nz) : -1, cells, aSeen, oStack, phase, ref bSurface);
                PushNeighbour(c, i < nx - 1 ? c + (ny * nz) : -1, cells, aSeen, oStack, phase, ref bSurface);
                PushNeighbour(c, j > 0 ? c - nz : -1, cells, aSeen, oStack, phase, ref bSurface);
                PushNeighbour(c, j < ny - 1 ? c + nz : -1, cells, aSeen, oStack, phase, ref bSurface);
                PushNeighbour(c, k > 0 ? c - 1 : -1, cells, aSeen, oStack, phase, ref bSurface);
                PushNeighbour(c, k < nz - 1 ? c + 1 : -1, cells, aSeen, oStack, phase, ref bSurface);
            }

            oClusters.Add(new Cluster(nSize, bSurface, iLo, iHi, jLo, jHi, kLo, kHi));
        }
        return oClusters;
    }

    private static void PushNeighbour(
        int from, int to, Phase[] cells, bool[] aSeen, Stack<int> oStack, Phase phase, ref bool bSurface)
    {
        if (to < 0) return;
        if (cells[to] == Phase.Outside) { bSurface = true; return; } // pore/solid against Outside = a surface
        if (cells[to] != phase || aSeen[to]) return;
        aSeen[to] = true;
        oStack.Push(to);
    }

    private static void ExtentsInside(
        in Grid grid, out int iLo, out int iHi, out int jLo, out int jHi, out int kLo, out int kHi)
    {
        Phase[] cells = grid.Cells;
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        iLo = nx; iHi = -1; jLo = ny; jHi = -1; kLo = nz; kHi = -1;
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                {
                    if (cells[((i * ny) + j) * nz + k] == Phase.Outside) continue;
                    if (i < iLo) iLo = i; if (i > iHi) iHi = i;
                    if (j < jLo) jLo = j; if (j > jHi) jHi = j;
                    if (k < kLo) kLo = k; if (k > kHi) kHi = k;
                }
    }
}
