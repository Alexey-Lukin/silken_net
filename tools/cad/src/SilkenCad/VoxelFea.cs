// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;

namespace SilkenCad;

// Voxel finite-element homogenisation of the Zone-1 lattice (00_07 HW.51 / HW.33).
//
// 🔴 WHY THIS EXISTS: the only stiffness number the canon had for this part came from Gibson-Ashby
// `E_foam/E_solid ≈ C·ρⁿ` quoted at the TEXTBOOK pair C = 1, n = 2 — and a wall_param sweep (verb
// `fea --fit`) measured that pair wrong: AXIALLY C ≈ 0.98, n ≈ 2.24; RADIALLY, on the shipped part after the
// HW.33 geometry verdict, BOTH members depart (C ≈ 0.55, n ≈ 1.71 at period/10 — before the verdict the
// exponent stayed near 2, n ≈ 1.93 at C ≈ 0.54, and only the coefficient departed) (01_01 §5.2 — which
// member is wrong is a property of the AXIS and of the geometry, not of the formula).
// ⚠️ The domain worry that first motivated this module — 1.50–2.50 cells across the radial wall,
// 01_01 §5.2 uncertainty (4) — was then MEASURED and costs almost nothing (the cube ladder is flat
// from one cell to eight). The verdict survived; its GROUND did not. This module measures the
// APPARENT stiffness of the real part instead.
//
// Method. Every Solid voxel of a Connectivity.Grid becomes one trilinear 8-node hexahedral element.
// All elements are identical cubes of the same isotropic material, so a SINGLE 24×24 element matrix
// is built once and the global operator is applied matrix-free, element by element — memory stays
// O(elements) and no sparse matrix is ever assembled. Solved by Jacobi-preconditioned conjugate
// gradients; the element loop is 8-coloured by voxel parity, so two elements of one colour can never
// share a node and the scatter is race-free under Parallel.For.
//
// 🔑 SELF-CALIBRATION rather than an analytic inversion. Every apparent modulus is reported as a
// RATIO to the identical test run on the identical envelope filled SOLID. For the axial case that
// solid run must return exactly E_solid (uniform uniaxial stress), which makes it a live validation
// of the element matrix, the assembly, the boundary conditions and the reaction sum in one number —
// see FeaTests. For the radial case no closed form is needed at all: the solid run IS the normaliser.
//
// ⚠️ DECLARED CEILING — what this measures and what it does not.
//   • Linear elastic, small strain, one isotropic solid phase. No plasticity, no contact, no buckling.
//   • Staircase boundaries, and the element's error is one-signed only within ONE run. Fully integrated
//     trilinear hexes are too stiff in bending (a NETWORK gyroid is bending-dominated), so one run's stiffness
//     under kinematic loading is never softer than the exact solution of that mesh — a sign that does not reach a
//     ratio of two runs (the radial column divides by the solid twin), a fit's intercept C or an off-diagonal
//     tensor term. The staircase changes the BODY — a voxel mesh cannot represent an inclined ligament surface —
//     and no specimen shows its sign: the phase-locked cube (picogk gotcha #16) moves its density with the step
//     and its ladders are not monotone, and the part's four-row sweep falls while its fits, read at the nominal
//     wall, sit above its /16 row at /32 (01_01 §5.2). Hence a number is quoted with its step sweep, or with its
//     step where it has none.
//   • It measures the part as MODELLED, i.e. the geometric intent. A face-offset SENSITIVITY exists since
//     2026-09-14 (`fea <cem> --dilate downskin|iso`): the lattice FIELD is dilated before sampling
//     (DilatedField, Zone1Anode.cs), so nothing in this class changed — and a dilated row is still intent
//     with a hypothetical offset, never the printed body. What the printed excess IS, per face orientation,
//     is a vendor answer nobody has given (00_07 HW.51).
//   • The ratio is to the solid ENVELOPE, so it already contains the free-surface size effect of the
//     real annular wall. That is the point; it is NOT a material property and must not be quoted as one.
//   • The RADIAL case is centred on the grid, so it is valid only on steps that divide the diameter
//     (RadialLoadCentreOffsetMm) — any other step is refused, not approximated.
//   • A CONSTANT-period lattice sampled at a step that divides its period is PHASE-LOCKED: a wall level
//     moves the voxel model only where it crosses one of the few field values sampled there, so a wall
//     sweep answers in a staircase and two walls can sample to one grid (PhaseLockCells). A collapsed
//     sweep is refused (IdenticalSweepGrids); a merely coarse staircase is not, and is read as noise in ρ.
internal static class VoxelFea
{
    // Poisson's ratio of the solid phase. Ti-6Al-4V ≈ 0.342 (and every bake-off candidate sits in
    // 0.30–0.37), so the choice moves the RATIO reported here by well under a percent — it is the
    // modulus that carries the alloy, and the modulus is factored out on purpose.
    internal const double SolidPoissonRatio = 0.342;

    internal enum LoadCase { AxialX, AxialY, AxialZ, Radial }

    internal readonly record struct FeaResult
    {
        public required LoadCase Case { get; init; }
        public required float StepMm { get; init; }
        public required int Elements { get; init; }
        public required int Dofs { get; init; }
        public required int Iterations { get; init; }
        public required double Residual { get; init; }
        public required bool Converged { get; init; }
        /// <summary>Apparent stiffness in units of E_solid — for an axial case this is E_app/E_solid.</summary>
        public required double StiffnessRatio { get; init; }
        /// <summary>Solid fraction of the sampled envelope actually meshed (islands already dropped).</summary>
        public required double SolidFraction { get; init; }
        /// <summary>Solid voxels discarded as not belonging to the largest face-connected body.</summary>
        public required double DiscardedIslandFraction { get; init; }
    }

    // ── Element matrix ───────────────────────────────────────────────────────────────────────────
    //
    // Trilinear hexahedron on a cube of side h, isotropic, E = 1. Built by 2×2×2 Gauss quadrature
    // rather than transcribed from a table: a transcribed matrix cannot be checked by reading it,
    // while this construction is checked by the solid-block test returning E exactly.
    // 🔑 The strain-displacement matrix and the elasticity matrix have ONE home each (below): the periodic
    // field analysis samples the same B at the same Gauss points, so the stress it reads and the energy this
    // matrix integrates cannot disagree about what a strain is — the Hill–Mandel pins would catch it if they did.

    // Corner signs in local order a*4 + b*2 + c with (a,b,c) ∈ {0,1}³ → (ξ,η,ζ) = (2a−1, 2b−1, 2c−1).
    private static readonly double[] s_aCornerXi = [-1, -1, -1, -1, 1, 1, 1, 1];
    private static readonly double[] s_aCornerEta = [-1, -1, 1, 1, -1, -1, 1, 1];
    private static readonly double[] s_aCornerZeta = [-1, 1, -1, 1, -1, 1, -1, 1];
    private static readonly double[] s_aGauss = [-1.0 / Math.Sqrt(3.0), 1.0 / Math.Sqrt(3.0)];

    // Isotropic elasticity, E = 1. Voigt order [xx, yy, zz, yz, zx, xy]; the shear rows carry engineering
    // strain, hence μ not 2μ.
    internal static double[,] IsotropicStiffness(double dNu)
    {
        double dLambda = dNu / ((1.0 + dNu) * (1.0 - (2.0 * dNu)));
        double dMu = 1.0 / (2.0 * (1.0 + dNu));
        var aD = new double[6, 6];
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++)
                aD[i, j] = dLambda + (i == j ? 2.0 * dMu : 0.0);
        for (int i = 3; i < 6; i++)
            aD[i, i] = dMu;
        return aD;
    }

    // B at one natural point (ξ, η, ζ), 6 × 24 row-major, engineering shear; dScale = 2/h (d/dx = (2/h) d/dξ).
    private static void StrainDisplacementAt(double dXi, double dEta, double dZeta, double dScale, double[] aB)
    {
        Array.Clear(aB);
        for (int n = 0; n < 8; n++)
        {
            double dNdx = 0.125 * s_aCornerXi[n] * (1 + (dEta * s_aCornerEta[n])) * (1 + (dZeta * s_aCornerZeta[n])) * dScale;
            double dNdy = 0.125 * s_aCornerEta[n] * (1 + (dXi * s_aCornerXi[n])) * (1 + (dZeta * s_aCornerZeta[n])) * dScale;
            double dNdz = 0.125 * s_aCornerZeta[n] * (1 + (dXi * s_aCornerXi[n])) * (1 + (dEta * s_aCornerEta[n])) * dScale;
            int ix = (3 * n) + 0, iy = (3 * n) + 1, iz = (3 * n) + 2;
            aB[(0 * 24) + ix] = dNdx;
            aB[(1 * 24) + iy] = dNdy;
            aB[(2 * 24) + iz] = dNdz;
            aB[(3 * 24) + iy] = dNdz; aB[(3 * 24) + iz] = dNdy; // γ_yz
            aB[(4 * 24) + ix] = dNdz; aB[(4 * 24) + iz] = dNdx; // γ_zx
            aB[(5 * 24) + ix] = dNdy; aB[(5 * 24) + iy] = dNdx; // γ_xy
        }
    }

    // The eight Gauss-point B matrices of a cube of side h, in the order the element matrix integrates them.
    private static double[][] GaussStrainDisplacement(double dSideMm)
    {
        double dScale = 2.0 / dSideMm;
        var aOut = new List<double[]>(8);
        foreach (double dXi in s_aGauss)
            foreach (double dEta in s_aGauss)
                foreach (double dZeta in s_aGauss)
                {
                    var aB = new double[6 * 24];
                    StrainDisplacementAt(dXi, dEta, dZeta, dScale, aB);
                    aOut.Add(aB);
                }
        return [.. aOut];
    }

    internal static double[] HexElementStiffness(double dSideMm, double dNu)
    {
        double[,] aD = IsotropicStiffness(dNu);
        double dDetJ = (dSideMm / 2.0) * (dSideMm / 2.0) * (dSideMm / 2.0);
        double dScale = 2.0 / dSideMm; // d/dx = (2/h) d/dξ

        var aK = new double[24 * 24];
        var aB = new double[6 * 24];

        foreach (double dXi in s_aGauss)
            foreach (double dEta in s_aGauss)
                foreach (double dZeta in s_aGauss)
                {
                    StrainDisplacementAt(dXi, dEta, dZeta, dScale, aB);

                    // K += Bᵀ D B · detJ (weights are 1 for 2-point Gauss).
                    var aDB = new double[6 * 24];
                    for (int r = 0; r < 6; r++)
                        for (int col = 0; col < 24; col++)
                        {
                            double dSum = 0.0;
                            for (int s = 0; s < 6; s++)
                                dSum += aD[r, s] * aB[(s * 24) + col];
                            aDB[(r * 24) + col] = dSum;
                        }
                    for (int rowDof = 0; rowDof < 24; rowDof++)
                        for (int colDof = 0; colDof < 24; colDof++)
                        {
                            double dSum = 0.0;
                            for (int s = 0; s < 6; s++)
                                dSum += aB[(s * 24) + rowDof] * aDB[(s * 24) + colDof];
                            aK[(rowDof * 24) + colDof] += dSum * dDetJ;
                        }
                }

        return aK;
    }

    // ── Mesh ─────────────────────────────────────────────────────────────────────────────────────

    private sealed class Mesh
    {
        public required int[] ElemNodes { get; init; }     // 8 node ids per element, flattened
        public required int[][] Colours { get; init; }     // element ids grouped by voxel parity (8 groups)
        public required int NodeCount { get; init; }
        public required float[] NodeX { get; init; }
        public required float[] NodeY { get; init; }
        public required float[] NodeZ { get; init; }
        public required int ElementCount { get; init; }
        public required double DiscardedIslandFraction { get; init; }
        public required double SolidFraction { get; init; }
        public required double NominalAreaMm2X { get; init; }
        public required double NominalAreaMm2Y { get; init; }
        public required double NominalAreaMm2Z { get; init; }
        public required double ExtentXMm { get; init; }
        public required double ExtentYMm { get; init; }
        public required double ExtentZMm { get; init; }
    }

    // Grid → hex mesh. Only the LARGEST face-connected solid body is meshed: a floating island has
    // rigid-body modes and would make the system singular, and it also carries no load in the real
    // part (nor current — 01_01 §1). What is dropped is reported, never absorbed.
    private static Mesh Build(in Connectivity.Grid grid, in bool[] aKeep, double dSolidFraction, double dDiscarded)
    {
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        float h = grid.StepMm;
        int nxNode = nx + 1, nyNode = ny + 1, nzNode = nz + 1;

        var aNodeId = new int[nxNode * nyNode * nzNode];
        Array.Fill(aNodeId, -1);

        var aElemCells = new List<int>();
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                {
                    int idx = grid.Index(i, j, k);
                    if (!aKeep[idx]) continue;
                    aElemCells.Add(idx);
                    for (int a = 0; a < 2; a++)
                        for (int b = 0; b < 2; b++)
                            for (int c = 0; c < 2; c++)
                                aNodeId[(((i + a) * nyNode) + j + b) * nzNode + k + c] = 0;
                }

        int nNodes = 0;
        for (int n = 0; n < aNodeId.Length; n++)
            if (aNodeId[n] == 0)
                aNodeId[n] = nNodes++;

        var aNodeX = new float[nNodes];
        var aNodeY = new float[nNodes];
        var aNodeZ = new float[nNodes];
        for (int i = 0; i < nxNode; i++)
            for (int j = 0; j < nyNode; j++)
                for (int k = 0; k < nzNode; k++)
                {
                    int id = aNodeId[((i * nyNode) + j) * nzNode + k];
                    if (id < 0) continue;
                    aNodeX[id] = i * h;
                    aNodeY[id] = j * h;
                    aNodeZ[id] = k * h;
                }

        int nElem = aElemCells.Count;
        var aElemNodes = new int[nElem * 8];
        var aColourLists = new List<int>[8];
        for (int c = 0; c < 8; c++) aColourLists[c] = [];

        for (int e = 0; e < nElem; e++)
        {
            int idx = aElemCells[e];
            int i = idx / (ny * nz);
            int j = (idx / nz) % ny;
            int k = idx % nz;
            for (int a = 0; a < 2; a++)
                for (int b = 0; b < 2; b++)
                    for (int c = 0; c < 2; c++)
                        aElemNodes[(e * 8) + (a * 4) + (b * 2) + c] =
                            aNodeId[(((i + a) * nyNode) + j + b) * nzNode + k + c];
            aColourLists[((i & 1) * 4) + ((j & 1) * 2) + (k & 1)].Add(e);
        }

        // Nominal cross-sections: the count of INSIDE (non-Outside) cells on a mid-slice, i.e. the
        // envelope's area, not the metal's. Apparent stress is force over the specimen's own section
        // — the same convention ISO 13314 uses for a porous compression coupon.
        double dAreaZ = SliceInsideCount(grid, 2, nz / 2) * h * (double)h;
        double dAreaX = SliceInsideCount(grid, 0, nx / 2) * h * (double)h;
        double dAreaY = SliceInsideCount(grid, 1, ny / 2) * h * (double)h;

        return new Mesh
        {
            ElemNodes = aElemNodes,
            Colours = [.. aColourLists.Select(l => l.ToArray())],
            NodeCount = nNodes,
            NodeX = aNodeX,
            NodeY = aNodeY,
            NodeZ = aNodeZ,
            ElementCount = nElem,
            DiscardedIslandFraction = dDiscarded,
            SolidFraction = dSolidFraction,
            NominalAreaMm2X = dAreaX,
            NominalAreaMm2Y = dAreaY,
            NominalAreaMm2Z = dAreaZ,
            ExtentXMm = nx * (double)h,
            ExtentYMm = ny * (double)h,
            ExtentZMm = nz * (double)h,
        };
    }

    private static long SliceInsideCount(in Connectivity.Grid grid, int iAxis, int iSlice)
    {
        long n = 0;
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
                for (int k = 0; k < grid.Nz; k++)
                {
                    if (iAxis == 0 && i != iSlice) continue;
                    if (iAxis == 1 && j != iSlice) continue;
                    if (iAxis == 2 && k != iSlice) continue;
                    if (grid.Cells[grid.Index(i, j, k)] != Phase.Outside) n++;
                }
        return n;
    }

    // ── Solver ───────────────────────────────────────────────────────────────────────────────────

    private sealed class System_
    {
        public required Mesh Mesh { get; init; }
        public required double[] Ke { get; init; }
        public required bool[] Fixed { get; init; }        // per DOF
        public required double[] Prescribed { get; init; } // per DOF, meaningful where Fixed
    }

    // y = K x, applied element by element. Colour groups are disjoint in their node sets, so the
    // scatter-add inside one group is race-free without atomics or per-thread buffers.
    private static void Multiply(System_ sys, double[] aX, double[] aY)
    {
        Array.Clear(aY);
        int[] aElemNodes = sys.Mesh.ElemNodes;
        double[] aKe = sys.Ke;
        foreach (int[] aColour in sys.Mesh.Colours)
        {
            if (aColour.Length == 0) continue;
            Parallel.For(0, aColour.Length, () => new double[48], (t, _, aScratch) =>
            {
                int e = aColour[t];
                double[] aLocalU = aScratch;
                int nBase = e * 8;
                for (int n = 0; n < 8; n++)
                {
                    int nd = aElemNodes[nBase + n] * 3;
                    aLocalU[(n * 3) + 0] = aX[nd + 0];
                    aLocalU[(n * 3) + 1] = aX[nd + 1];
                    aLocalU[(n * 3) + 2] = aX[nd + 2];
                }
                for (int r = 0; r < 24; r++)
                {
                    double dSum = 0.0;
                    int nRow = r * 24;
                    for (int c = 0; c < 24; c++)
                        dSum += aKe[nRow + c] * aLocalU[c];
                    aLocalU[24 + r] = dSum;
                }
                for (int n = 0; n < 8; n++)
                {
                    int nd = aElemNodes[nBase + n] * 3;
                    aY[nd + 0] += aLocalU[24 + (n * 3) + 0];
                    aY[nd + 1] += aLocalU[24 + (n * 3) + 1];
                    aY[nd + 2] += aLocalU[24 + (n * 3) + 2];
                }
                return aScratch;
            }, _ => { });
        }
    }

    private static double[] Diagonal(System_ sys)
    {
        var aDiag = new double[sys.Mesh.NodeCount * 3];
        int[] aElemNodes = sys.Mesh.ElemNodes;
        for (int e = 0; e < sys.Mesh.ElementCount; e++)
            for (int n = 0; n < 8; n++)
            {
                int nd = aElemNodes[(e * 8) + n] * 3;
                for (int d = 0; d < 3; d++)
                {
                    int local = (n * 3) + d;
                    aDiag[nd + d] += sys.Ke[(local * 24) + local];
                }
            }
        return aDiag;
    }

    // Jacobi-preconditioned CG on the FREE DOFs. The fixed set is handled by projection rather than
    // by penalty: the operator zeroes fixed rows AND the input's fixed entries, so the iterate never
    // leaves the free subspace and no artificial stiffness is introduced. `aLoad` is an external nodal
    // force (the periodic case's macro-strain load); null keeps the arithmetic of every boundary case
    // bit for bit, which is why it is a separate branch rather than a zero vector.
    private static (double[] U, int Iterations, double Residual, bool Converged) Solve(
        System_ sys, double dTol, int nMaxIter, double[]? aLoad = null)
    {
        int nDof = sys.Mesh.NodeCount * 3;
        var aUc = new double[nDof];
        for (int d = 0; d < nDof; d++)
            if (sys.Fixed[d]) aUc[d] = sys.Prescribed[d];

        var aTmp = new double[nDof];
        Multiply(sys, aUc, aTmp);
        var aB = new double[nDof];
        for (int d = 0; d < nDof; d++)
            aB[d] = sys.Fixed[d] ? 0.0 : aLoad is null ? -aTmp[d] : aLoad[d] - aTmp[d];

        double[] aDiag = Diagonal(sys);
        var aInv = new double[nDof];
        for (int d = 0; d < nDof; d++)
            aInv[d] = sys.Fixed[d] || aDiag[d] <= 0.0 ? 0.0 : 1.0 / aDiag[d];

        var aX = new double[nDof];
        var aR = (double[])aB.Clone();
        var aZ = new double[nDof];
        for (int d = 0; d < nDof; d++) aZ[d] = aInv[d] * aR[d];
        var aP = (double[])aZ.Clone();
        var aAp = new double[nDof];

        double dNormB = Math.Sqrt(Dot(aB, aB));
        if (dNormB == 0.0)
            return (aUc, 0, 0.0, true);

        double dRz = Dot(aR, aZ);
        int nIter = 0;
        double dRes = 1.0;
        for (; nIter < nMaxIter; nIter++)
        {
            ApplyProjected(sys, aP, aAp);
            double dPap = Dot(aP, aAp);
            if (dPap <= 0.0) break;
            double dAlpha = dRz / dPap;
            for (int d = 0; d < nDof; d++)
            {
                aX[d] += dAlpha * aP[d];
                aR[d] -= dAlpha * aAp[d];
            }
            dRes = Math.Sqrt(Dot(aR, aR)) / dNormB;
            if (dRes < dTol) { nIter++; break; }
            for (int d = 0; d < nDof; d++) aZ[d] = aInv[d] * aR[d];
            double dRzNew = Dot(aR, aZ);
            double dBeta = dRzNew / dRz;
            for (int d = 0; d < nDof; d++) aP[d] = aZ[d] + (dBeta * aP[d]);
            dRz = dRzNew;
        }

        for (int d = 0; d < nDof; d++) aX[d] += aUc[d];
        return (aX, nIter, dRes, dRes < dTol);
    }

    private static void ApplyProjected(System_ sys, double[] aX, double[] aY)
    {
        Multiply(sys, aX, aY);
        for (int d = 0; d < aY.Length; d++)
            if (sys.Fixed[d]) aY[d] = 0.0;
    }

    private static double Dot(double[] a, double[] b)
    {
        double d = 0.0;
        for (int i = 0; i < a.Length; i++) d += a[i] * b[i];
        return d;
    }

    // ── Load cases ───────────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Apparent modulus along one axis, as a fraction of E_solid. Platens are FRICTIONLESS by
    /// default: only the load-direction DOF is prescribed on the two end faces, so the lattice is
    /// free to contract laterally and the number is the specimen's own stiffness, not the platen's
    /// grip. `bBonded` switches to the other extreme (all three DOFs held) — the two together
    /// bracket a real test, which is why both are reported rather than one being called correct.
    /// </summary>
    internal static FeaResult ApparentAxialModulus(
        in Connectivity.Grid grid, int iAxis, bool bBonded = false, double dTol = 1e-8, int nMaxIter = 200_000)
    {
        (bool[] aKeep, double dSolid, double dDiscarded) = LargestSolidBody(grid);
        Mesh mesh = Build(grid, aKeep, dSolid, dDiscarded);
        double[] aKe = HexElementStiffness(grid.StepMm, SolidPoissonRatio);

        int nDof = mesh.NodeCount * 3;
        var aFixed = new bool[nDof];
        var aPres = new double[nDof];

        double dExtent = iAxis switch { 0 => mesh.ExtentXMm, 1 => mesh.ExtentYMm, _ => mesh.ExtentZMm };
        double dArea = iAxis switch { 0 => mesh.NominalAreaMm2X, 1 => mesh.NominalAreaMm2Y, _ => mesh.NominalAreaMm2Z };
        const double dStrain = 1e-3; // linear problem — magnitude cancels; kept small and explicit
        double dDelta = dStrain * dExtent;

        float fTolPos = 0.25f * grid.StepMm;
        var aLoadedHi = new List<int>();
        for (int n = 0; n < mesh.NodeCount; n++)
        {
            double dPos = iAxis switch { 0 => mesh.NodeX[n], 1 => mesh.NodeY[n], _ => mesh.NodeZ[n] };
            bool bLo = dPos < fTolPos;
            bool bHi = dPos > dExtent - fTolPos;
            if (!bLo && !bHi) continue;
            if (bBonded)
                for (int d = 0; d < 3; d++) { aFixed[(n * 3) + d] = true; aPres[(n * 3) + d] = 0.0; }
            aFixed[(n * 3) + iAxis] = true;
            aPres[(n * 3) + iAxis] = bHi ? -dDelta : 0.0;
            if (bHi) aLoadedHi.Add(n);
        }

        // Frictionless platens leave three rigid-body modes (two translations + one rotation about
        // the load axis). Pin them on two nodes rather than by averaging constraints: the pinned
        // DOFs carry no reaction in the load direction, so the measured modulus is untouched.
        if (!bBonded)
            PinTransverseRigidModes(mesh, iAxis, aFixed, aPres);

        var sys = new System_ { Mesh = mesh, Ke = aKe, Fixed = aFixed, Prescribed = aPres };
        (double[] aU, int nIter, double dRes, bool bConv) = Solve(sys, dTol, nMaxIter);

        var aF = new double[nDof];
        Multiply(sys, aU, aF);
        double dForce = 0.0;
        foreach (int n in aLoadedHi) dForce += aF[(n * 3) + iAxis];

        double dStress = Math.Abs(dForce) / dArea;
        return new FeaResult
        {
            Case = iAxis switch { 0 => LoadCase.AxialX, 1 => LoadCase.AxialY, _ => LoadCase.AxialZ },
            StepMm = grid.StepMm,
            Elements = mesh.ElementCount,
            Dofs = nDof,
            Iterations = nIter,
            Residual = dRes,
            Converged = bConv,
            StiffnessRatio = dStress / dStrain,
            SolidFraction = mesh.SolidFraction,
            DiscardedIslandFraction = mesh.DiscardedIslandFraction,
        };
    }

    private static void PinTransverseRigidModes(Mesh mesh, int iAxis, bool[] aFixed, double[] aPres)
    {
        int iA = (iAxis + 1) % 3, iB = (iAxis + 2) % 3;
        double Coord(int n, int axis) => axis switch { 0 => mesh.NodeX[n], 1 => mesh.NodeY[n], _ => mesh.NodeZ[n] };

        // Two nodes far apart in the iA direction: the first kills both transverse translations, the
        // second kills the rotation about the load axis.
        int nFirst = 0, nSecond = 0;
        double dMin = double.MaxValue, dMax = double.MinValue;
        for (int n = 0; n < mesh.NodeCount; n++)
        {
            double c = Coord(n, iA);
            if (c < dMin) { dMin = c; nFirst = n; }
            if (c > dMax) { dMax = c; nSecond = n; }
        }
        aFixed[(nFirst * 3) + iA] = true; aPres[(nFirst * 3) + iA] = 0.0;
        aFixed[(nFirst * 3) + iB] = true; aPres[(nFirst * 3) + iB] = 0.0;
        aFixed[(nSecond * 3) + iB] = true; aPres[(nSecond * 3) + iB] = 0.0;
    }

    // 🔴 The radial load is centred on the GRID, and the grid sits on the part axis only when 2R/step is a
    // whole number. The FE sampler starts at −R and rounds the cell count UP, so a step that does not divide
    // the diameter adds an empty column and walks the centre off the axis — on Ø11 at period 2.0 the odd
    // divisors do it (/7: a quarter step, 71 µm; /11: 45 µm, measured 2026-09-14). The prescribed
    // displacement then presses one side of the rim deeper than the other, i.e. it loads a different part,
    // and nothing in the result says so. Axial cases never read the centre. REFUSED rather than re-centred:
    // re-centring moves the last bits of every ALIGNED radial number already pinned to canon (01_01 §5.2),
    // so the committed caches would stop reproducing from this code.
    internal const double RadialCentreToleranceMm = 1e-4;

    /// <summary>How far the radial load centre (half the grid extent) sits from the part axis, in mm.</summary>
    internal static double RadialLoadCentreOffsetMm(in Connectivity.Grid grid, double dOuterRadiusMm)
        => Math.Max(Math.Abs((grid.Nx * (double)grid.StepMm / 2.0) - dOuterRadiusMm),
                    Math.Abs((grid.Ny * (double)grid.StepMm / 2.0) - dOuterRadiusMm));

    // 🔴 A CONSTANT-period lattice sampled at a step that divides its period is PHASE-LOCKED: the sampler puts every
    // cell's points at the same phases, so the field takes a small discrete set of values there, and a wall level
    // moves the voxel model only when it crosses one of them. Measured 2026-09-14 on graded_porosity (period 2.0,
    // Ø11) with the wall held uniform, as `fea --fit` holds it: at /4 ten walls from −0.60 to 0.40 gave THREE
    // porosities; at /8 and at /10 the walls −0.15 and −0.08 sampled to one grid, and at /8 so did 0.10. The pine
    // part, whose period is graded 2.5 → 2.0, drifts the phase with radius and gave ten porosities for the same ten
    // walls. ⚠️ `--step-div N` takes the step FROM the period (period/N), so on a constant-period part EVERY divisor is
    // locked by definition, aligned or not; the radial pre-check only narrows the way out — a radial sweep needs a
    // step that is a fraction of the diameter and NOT of the period (`--step-mm`, e.g. 11/50 on Ø11 at period 2.0).
    // The lattice cube is locked by construction; its fits read the staircase as scatter that shrinks with steps per
    // period. Returns how many cells the sampled phase takes to repeat (1 = every cell, the --step-div case), or 0
    // when it does not repeat within nMaxCells — unlocked at the scale of anything sampled here.
    // ⊕ A STEPPED part (`bZoned`) keeps a constant period in EACH zone, so a step dividing one zone's period locks that
    // zone whole — in-plane and along z — while the other may still resolve every wall, and IdenticalSweepGrids does not
    // refuse such a sweep (the unlocked zone differs). Its lock is the tighter of the two zones'. Found by the review of
    // the axial-lock change, 2026-10-22: before it this returned 0 for every stepped step.
    internal static int PhaseLockCells(float fStepMm, float fPeriodCoreMm, float fPeriodRimMm, bool bZoned = false, int nMaxCells = 4)
    {
        float fPeriodRim = fPeriodRimMm > 0f ? fPeriodRimMm : fPeriodCoreMm;
        if (fPeriodRim == fPeriodCoreMm)
            return RepeatCells(fStepMm, fPeriodCoreMm, nMaxCells);
        if (!bZoned)
            return 0;
        int nCore = RepeatCells(fStepMm, fPeriodCoreMm, nMaxCells), nRim = RepeatCells(fStepMm, fPeriodRim, nMaxCells);
        return nCore == 0 ? nRim : nRim == 0 ? nCore : Math.Min(nCore, nRim);
    }

    // The PART's lock — one home for every caller (the fea verbs' line, its --fit hint and the pins), so none of them
    // re-derives whether the two periods are zones (stepped) or a gradient (graded).
    internal static int PhaseLockCells(float fStepMm, AnchorCem cem)
        => PhaseLockCells(fStepMm, cem.GyroidPeriodMm, cem.GyroidPeriodRimMm, IsZoned(cem));

    // Where the part's full lock sits, in the verbs' words; null when the part does not lock whole.
    internal static string? PhaseLockWhere(float fStepMm, AnchorCem cem)
    {
        if (PhaseLockCells(fStepMm, cem) == 0)
            return null;
        if (!IsZoned(cem) || cem.GyroidPeriodRimMm <= 0f || cem.GyroidPeriodRimMm == cem.GyroidPeriodMm)
            return "constant period";
        bool bCore = RepeatCells(fStepMm, cem.GyroidPeriodMm) > 0, bRim = RepeatCells(fStepMm, cem.GyroidPeriodRimMm) > 0;
        return bCore && bRim ? "constant period in both zones"
            : $"constant period in the {(bRim ? "rim" : "core")} zone only — the other zone may still resolve every wall";
    }

    private static bool IsZoned(AnchorCem cem) => cem.Topology.Equals("stepped", StringComparison.OrdinalIgnoreCase);

    // ⊕ 2026-10-22, HW.33 (в): the graded part is constant-period ALONG z (Zone1Anode.AxialPeriodMm — the rim's) while
    // its in-plane phase still drifts with radius. No wall staircase, then (PhaseLockCells stays 0, and the sampled pin
    // in VoxelFeaTests shows close walls resolving on the shipped pine part), but a step that divides the axial period
    // samples every axial cell at the same z-phases, so the step's discretization error is coherent along the axis
    // instead of averaging out — the named likely cause of the post-verdict sweep's non-monotonicity (01_01 §5.2), which
    // the HW.23 Richardson re-sweep separates with locked ⊥ unlocked steps. Same return as above, along z only.
    internal static int AxialPhaseLockCells(float fStepMm, float fPeriodAxialMm, int nMaxCells = 4)
        => RepeatCells(fStepMm, fPeriodAxialMm, nMaxCells);

    // How many cells the sampled phase of ONE constant period takes to repeat; 0 when it does not within nMaxCells, or
    // when there is no single period (≤ 0).
    internal static int RepeatCells(float fStepMm, float fPeriodMm, int nMaxCells = 4)
    {
        if (fPeriodMm <= 0f)
            return 0;
        double dStepsPerPeriod = fPeriodMm / (double)fStepMm;
        for (int nCells = 1; nCells <= nMaxCells; nCells++)
        {
            double dSteps = dStepsPerPeriod * nCells;
            if (Math.Abs(dSteps - Math.Round(dSteps)) < 1e-4 * nCells)
                return nCells;
        }
        return 0;
    }

    // A sweep point whose grid another point already produced measured nothing new: it is the staircase above, not a
    // second density. Compared CELL BY CELL rather than by porosity — an equal solid count is not equal geometry,
    // and what is being refused is precisely "the sweep varied nothing here".
    internal static List<(float WallA, float WallB)> IdenticalSweepGrids(IReadOnlyList<(float Wall, Connectivity.Grid Grid)> aSamples)
    {
        var aPairs = new List<(float WallA, float WallB)>();
        for (int i = 0; i < aSamples.Count; i++)
        {
            for (int j = i + 1; j < aSamples.Count; j++)
            {
                Connectivity.Grid a = aSamples[i].Grid, b = aSamples[j].Grid;
                if (a.Nx == b.Nx && a.Ny == b.Ny && a.Nz == b.Nz && a.Cells.SequenceEqual(b.Cells))
                    aPairs.Add((aSamples[i].Wall, aSamples[j].Wall));
            }
        }
        return aPairs;
    }

    /// <summary>
    /// Radial stiffness of the part's cross-section (the whole disc since the welded branch removed the core):
    /// a uniform inward radial displacement is imposed on the outer boundary shell, the two end faces are held
    /// in the axial direction (plane-strain surrogate for a part much longer than its radius), and the inward
    /// reaction is summed. Reported as an average
    /// radial pressure divided by diametral strain, in units of E_solid — the SAME test on the solid
    /// envelope is the normaliser, so no thick-cylinder inversion is needed and none is assumed.
    /// This is the load the press-fit and the tree's own swelling apply (01_01 §4.2).
    /// </summary>
    internal static FeaResult RadialStiffness(
        in Connectivity.Grid grid, double dOuterRadiusMm, double dTol = 1e-8, int nMaxIter = 200_000)
    {
        double dCentreOffset = RadialLoadCentreOffsetMm(grid, dOuterRadiusMm);
        if (dCentreOffset > RadialCentreToleranceMm)
            throw new InvalidOperationException(
                $"radial load centre sits {dCentreOffset * 1000.0:F1} µm off the part axis: 2R/step = " +
                $"{2.0 * dOuterRadiusMm / grid.StepMm:F3} is not a whole number, so the prescribed displacement would " +
                "press one side of the rim deeper than the other — pick a step divisor that divides the diameter");

        (bool[] aKeep, double dSolid, double dDiscarded) = LargestSolidBody(grid);
        Mesh mesh = Build(grid, aKeep, dSolid, dDiscarded);
        double[] aKe = HexElementStiffness(grid.StepMm, SolidPoissonRatio);

        int nDof = mesh.NodeCount * 3;
        var aFixed = new bool[nDof];
        var aPres = new double[nDof];

        double dCx = mesh.ExtentXMm / 2.0, dCy = mesh.ExtentYMm / 2.0;
        double dShell = dOuterRadiusMm - grid.StepMm;
        const double dStrain = 1e-3;
        double dDelta = dStrain * dOuterRadiusMm;

        float fTolPos = 0.25f * grid.StepMm;
        var aLoaded = new List<int>();
        for (int n = 0; n < mesh.NodeCount; n++)
        {
            if (mesh.NodeZ[n] < fTolPos || mesh.NodeZ[n] > mesh.ExtentZMm - fTolPos)
                aFixed[(n * 3) + 2] = true;

            double dx = mesh.NodeX[n] - dCx, dy = mesh.NodeY[n] - dCy;
            double dR = Math.Sqrt((dx * dx) + (dy * dy));
            if (dR < dShell || dR == 0.0) continue;
            aFixed[(n * 3) + 0] = true; aPres[(n * 3) + 0] = -dDelta * dx / dR;
            aFixed[(n * 3) + 1] = true; aPres[(n * 3) + 1] = -dDelta * dy / dR;
            aLoaded.Add(n);
        }

        var sys = new System_ { Mesh = mesh, Ke = aKe, Fixed = aFixed, Prescribed = aPres };
        (double[] aU, int nIter, double dRes, bool bConv) = Solve(sys, dTol, nMaxIter);

        var aF = new double[nDof];
        Multiply(sys, aU, aF);
        double dRadialForce = 0.0;
        foreach (int n in aLoaded)
        {
            double dx = mesh.NodeX[n] - dCx, dy = mesh.NodeY[n] - dCy;
            double dR = Math.Sqrt((dx * dx) + (dy * dy));
            dRadialForce += -((aF[(n * 3) + 0] * dx) + (aF[(n * 3) + 1] * dy)) / dR;
        }

        double dLateralArea = 2.0 * Math.PI * dOuterRadiusMm * mesh.ExtentZMm;
        double dPressure = Math.Abs(dRadialForce) / dLateralArea;
        return new FeaResult
        {
            Case = LoadCase.Radial,
            StepMm = grid.StepMm,
            Elements = mesh.ElementCount,
            Dofs = nDof,
            Iterations = nIter,
            Residual = dRes,
            Converged = bConv,
            StiffnessRatio = dPressure / dStrain,
            SolidFraction = mesh.SolidFraction,
            DiscardedIslandFraction = mesh.DiscardedIslandFraction,
        };
    }

    // ── Periodic homogenisation (00_07 HW.23) ────────────────────────────────────────────────────
    //
    // 🔴 WHY THIS EXISTS: every case above loads a FINITE specimen through its boundary, and a finite lattice specimen has
    // no unique stiffness — on one volume of whole cells a kinematic boundary reads it high and a traction boundary low
    // (the radial case above is neither: its shell fixes the radial DOFs only, and it runs on a graded part), and the two
    // meet only as the specimen grows (Huet 1990, J. Mech. Phys. Solids 38:813; Kanit et al. 2003, Int. J. Solids Struct.
    // 40:3647). Off the cube axis script `106` needs the lattice's SHEAR modulus C44, which none of the four cases above
    // measures, and `105`'s bound needs the in-plane modulus under uniaxial STRESS and the ligaments' peak over their RMS —
    // a stress field, not a stiffness. On an exactly periodic lattice all three are properties of the INFINITE lattice,
    // and periodic boundary conditions on one period cell return them with no boundary at all.
    //
    // Method. The grid is read as one period cell: node (i, j, k) wraps onto (i mod Nx, j mod Ny, k mod Nz), so the mesh
    // is a 3-torus whose faces are glued to their opposites. A unit macro strain E enters as u = E·x + ũ with ũ periodic.
    // Ke annihilates a translation, so every element feels the same load Ke·(E·x_local) and the fluctuation solves
    // K·ũ = −Σ Ke·(E·x_local) with ONE node pinned — the torus has exactly three zero modes, the translations (a rotation
    // is not periodic). The macro stress is the Gauss-point average over the WHOLE cell, pores at σ = 0, so one solve is
    // one column of C and six unit strains give the tensor. A uniaxial macro stress Σ along any direction is then the
    // superposition ε̄ = C⁻¹Σ of the six solved fields, read at the same Gauss points the element matrix integrates.
    //
    // ⚠️ DECLARED CEILING.
    //   • A MATERIAL property of the infinite lattice at the sampled level — not the shipped part, which is finite (Ø11, a
    //     few cells across), graded (period 2.5 → 2.0) and cut at its rim. Read beside the part's own cases, never in place
    //     of them; which of the two a consumer needs is the consumer's reading to name.
    //   • The same staircase and fully integrated hexes as every case here, but a period cell is phase-locked by
    //     construction (picogk gotcha #16), so the staircase reads as SCATTER along the ladder, and these rows do not show
    //     the sign of the bias — the tensor is quoted with its steps-per-period ladder.
    //   • The cell must be EXACTLY periodic: a whole number of periods sampled at cell centres (SampleLatticeCube). The
    //     colouring needs an even cell count on every axis — an odd one glues two elements of one colour across the wrap —
    //     so an odd count is refused, as is any Outside cell (a period cell has no outside).
    //   • A field MAXIMUM does not converge along the steps ladder — on the gyroid it does not settle along the
    //     ladder (01_01 §5.2), and where it sits is not located — so the field is read by QUANTILES over the
    //     ladder and the maximum is never a reading.
    //   • ⚠️ Hill–Mandel (HillMandelWorst) is an IDENTITY of this formulation, not a check of the solution: CG from a zero
    //     start keeps the iterate orthogonal to its residual, so the averaged stress equals 2W/V at ANY iterate. It catches
    //     a stress readout inconsistent with the energy (another B, another point, another sign), nothing else; the
    //     solution is held by the closed-form pins and the CG residual.

    /// <summary>The quantiles the stress field is read at; the last is the maximum, which does not converge along the ladder — never a reading.</summary>
    internal static readonly double[] FieldQuantiles = [0.50, 0.90, 0.99, 0.999, 1.0];

    internal readonly record struct UniaxialField
    {
        public required double ThetaDeg { get; init; }
        /// <summary>E along (cos θ, sin θ, 0) under uniaxial macro STRESS, from the full tensor, in units of E_solid.</summary>
        public required double ModulusRatio { get; init; }
        /// <summary>σ_W = √(2·E_s·⟨w⟩_solid), the RMS energy-equivalent stress over the metal, per unit macro stress.</summary>
        public required double SigmaWPerMacroStress { get; init; }
        /// <summary>|2·φ·⟨w⟩_solid·E_dir − 1|: the field's energy against the tensor's — Hill–Mandel on the field.</summary>
        public required double EnergyIdentityResidual { get; init; }
        /// <summary>max|σ_i| / σ_W at FieldQuantiles, over the Gauss points (equal volumes).</summary>
        public required double[] PrincipalOverSigmaW { get; init; }
        /// <summary>von Mises / σ_W at FieldQuantiles.</summary>
        public required double[] VonMisesOverSigmaW { get; init; }
        /// <summary>Share of the metal's volume where max|σ_i| exceeds σ_W.</summary>
        public required double ShareAboveSigmaW { get; init; }
    }

    internal sealed class PeriodicResult
    {
        public required float StepMm { get; init; }
        public required int Elements { get; init; }
        public required int Dofs { get; init; }
        /// <summary>Solid fraction of the cell actually meshed (islands already dropped).</summary>
        public required double SolidFraction { get; init; }
        /// <summary>Solid voxels discarded as not belonging to the largest body ON THE TORUS.</summary>
        public required double DiscardedIslandFraction { get; init; }
        /// <summary>Effective stiffness, Voigt [xx, yy, zz, yz, zx, xy] with engineering shear, in units of E_solid;
        /// column k is the macro stress under the k-th unit macro strain.</summary>
        public required double[,] C { get; init; }
        public required int[] Iterations { get; init; }
        public required double[] Residuals { get; init; }
        public required bool Converged { get; init; }
        /// <summary>max_k |C_kk − 2W_k/V| over max_j |C_jj| — the averaged stress against the strain energy, per case.</summary>
        public required double HillMandelWorst { get; init; }
        /// <summary>max |C_ij − C_ji| over max_j |C_jj| — reciprocity of two independent solves.</summary>
        public required double ReciprocityWorst { get; init; }
        public required UniaxialField[] Fields { get; init; }
    }

    /// <summary>
    /// Effective stiffness of a periodic lattice from one period cell, plus — for each in-plane angle θ (from [100] in the
    /// (001) plane) — the ligament stress field under a unit uniaxial macro stress along (cos θ, sin θ, 0).
    /// </summary>
    internal static PeriodicResult PeriodicHomogenization(
        in Connectivity.Grid grid, IReadOnlyList<double>? aThetaDeg = null, double dTol = 1e-8, int nMaxIter = 200_000)
    {
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        if (nx < 2 || ny < 2 || nz < 2 || nx % 2 != 0 || ny % 2 != 0 || nz % 2 != 0)
            throw new ArgumentException(
                $"a period cell needs an even cell count of at least 2 on every axis, got {nx}×{ny}×{nz}: an odd count glues " +
                "two elements of one colour across the wrap", nameof(grid));
        if (Array.IndexOf(grid.Cells, Phase.Outside) >= 0)
            throw new ArgumentException("a period cell has no outside — every cell must be solid or pore", nameof(grid));

        bool[] aKeep = Connectivity.LargestComponentMask(grid, Phase.Solid, bPeriodic: true);
        long nSolid = 0, nKept = 0;
        for (int n = 0; n < grid.Cells.Length; n++)
        {
            if (grid.Cells[n] == Phase.Solid) nSolid++;
            if (aKeep[n]) nKept++;
        }
        if (nKept == 0)
            throw new ArgumentException("the period cell holds no solid", nameof(grid));

        Mesh mesh = BuildPeriodic(grid, aKeep, (double)nKept / grid.Cells.Length, 1.0 - ((double)nKept / nSolid));
        double h = grid.StepMm;
        double[] aKe = HexElementStiffness(h, SolidPoissonRatio);
        double[,] aD = IsotropicStiffness(SolidPoissonRatio);
        double[][] aBg = GaussStrainDisplacement(h);
        double dGaussVolume = h * h * h / 8.0;
        double dCellVolume = nx * (double)ny * nz * h * h * h;

        int nDof = mesh.NodeCount * 3;
        var aFixed = new bool[nDof];
        aFixed[0] = aFixed[1] = aFixed[2] = true; // node 0 pinned — the torus's three translations, nothing else
        var sys = new System_ { Mesh = mesh, Ke = aKe, Fixed = aFixed, Prescribed = new double[nDof] };

        var aC = new double[6, 6];
        var aTwoWOverV = new double[6];
        var aIter = new int[6];
        var aRes = new double[6];
        var aU0 = new double[6][];
        var aFluct = new double[6][];
        bool bConverged = true;
        for (int k = 0; k < 6; k++)
        {
            aU0[k] = UnitStrainNodalDisplacement(k, h);
            double[] aFe = MultiplyElement(aKe, aU0[k]);
            var aLoad = new double[nDof];
            for (int e = 0; e < mesh.ElementCount; e++)
                for (int n = 0; n < 8; n++)
                {
                    int nd = mesh.ElemNodes[(e * 8) + n] * 3;
                    for (int d = 0; d < 3; d++) aLoad[nd + d] -= aFe[(n * 3) + d];
                }

            (double[] aU, int nIter, double dRes, bool bConv) = Solve(sys, dTol, nMaxIter, aLoad);
            aFluct[k] = aU;
            aIter[k] = nIter;
            aRes[k] = dRes;
            bConverged &= bConv;

            (double[] aSigmaV, double dEnergy) = CellIntegrals(mesh, aKe, aD, aBg, aU0[k], aU, dGaussVolume);
            for (int i = 0; i < 6; i++) aC[i, k] = aSigmaV[i] / dCellVolume;
            aTwoWOverV[k] = 2.0 * dEnergy / dCellVolume;
        }

        double dDiagMax = 0.0, dHillMandel = 0.0, dReciprocity = 0.0;
        for (int k = 0; k < 6; k++) dDiagMax = Math.Max(dDiagMax, Math.Abs(aC[k, k]));
        for (int k = 0; k < 6; k++)
        {
            dHillMandel = Math.Max(dHillMandel, Math.Abs(aC[k, k] - aTwoWOverV[k]) / dDiagMax);
            for (int j = 0; j < 6; j++)
                dReciprocity = Math.Max(dReciprocity, Math.Abs(aC[j, k] - aC[k, j]) / dDiagMax);
        }

        UniaxialField[] aFields = [.. (aThetaDeg ?? []).Select(th =>
            UniaxialStressField(th, aC, mesh, aD, aBg, aU0, aFluct, mesh.SolidFraction))];

        return new PeriodicResult
        {
            StepMm = grid.StepMm,
            Elements = mesh.ElementCount,
            Dofs = nDof,
            SolidFraction = mesh.SolidFraction,
            DiscardedIslandFraction = mesh.DiscardedIslandFraction,
            C = aC,
            Iterations = aIter,
            Residuals = aRes,
            Converged = bConverged,
            HillMandelWorst = dHillMandel,
            ReciprocityWorst = dReciprocity,
            Fields = aFields,
        };
    }

    /// <summary>The cubic reading of a tensor: the three independent constants averaged over their equivalent entries.</summary>
    internal readonly record struct CubicReading
    {
        public required double C11 { get; init; }
        public required double C12 { get; init; }
        public required double C44 { get; init; }
        /// <summary>Largest relative spread inside one group of cubic-equivalent entries (C11-type · C12-type · C44-type).</summary>
        public required double EquivalentSpread { get; init; }
        /// <summary>Largest entry cubic symmetry sets to zero, over C11.</summary>
        public required double OffCubicMax { get; init; }
        /// <summary>Poisson's ratio under uniaxial stress along a cube axis.</summary>
        public double Nu => C12 / (C11 + C12);
        public double E100 => (C11 - C12) * (C11 + (2.0 * C12)) / (C11 + C12);
        /// <summary>1/E[110] = (S11 + S12)/2 + S44/4, with S11 + S12 = C11/((C11 − C12)(C11 + 2·C12)) and S44 = 1/C44.</summary>
        public double E110 => 1.0 / ((C11 / ((C11 - C12) * (C11 + (2.0 * C12))) / 2.0) + (1.0 / (4.0 * C44)));
        /// <summary>Zener ratio 2·C44/(C11 − C12): 1 is isotropic.</summary>
        public double Zener => 2.0 * C44 / (C11 - C12);
    }

    internal static CubicReading Cubic(double[,] aC)
    {
        double[] aNormal = [aC[0, 0], aC[1, 1], aC[2, 2]];
        double[] aCross = [aC[0, 1], aC[1, 0], aC[0, 2], aC[2, 0], aC[1, 2], aC[2, 1]];
        double[] aShear = [aC[3, 3], aC[4, 4], aC[5, 5]];
        static double Spread(double[] a) => (a.Max() - a.Min()) / Math.Abs(a.Average());
        double dC11 = aNormal.Average();
        double dOff = 0.0;
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
            {
                bool bCubic = (i < 3 && j < 3) || (i == j);
                if (!bCubic) dOff = Math.Max(dOff, Math.Abs(aC[i, j]));
            }
        return new CubicReading
        {
            C11 = dC11,
            C12 = aCross.Average(),
            C44 = aShear.Average(),
            EquivalentSpread = Math.Max(Spread(aNormal), Math.Max(Spread(aCross), Spread(aShear))),
            OffCubicMax = dOff / dC11,
        };
    }

    // Grid → hex mesh on the 3-torus: lattice point (i, j, k) wraps onto (i mod Nx, …), so a cell on the far face shares
    // its nodes with the cell on the near face. Node coordinates are the near-face copies and the periodic case never reads
    // them: its load is E·x LOCAL to each element, so the wrap never enters it, and the pinned node is simply node 0.
    private static Mesh BuildPeriodic(in Connectivity.Grid grid, in bool[] aKeep, double dSolidFraction, double dDiscarded)
    {
        int nx = grid.Nx, ny = grid.Ny, nz = grid.Nz;
        float h = grid.StepMm;
        int Wrap(int i, int j, int k) => ((((i % nx) * ny) + (j % ny)) * nz) + (k % nz);

        var aNodeId = new int[nx * ny * nz];
        Array.Fill(aNodeId, -1);
        var aElemCells = new List<int>();
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
                for (int k = 0; k < nz; k++)
                {
                    int idx = grid.Index(i, j, k);
                    if (!aKeep[idx]) continue;
                    aElemCells.Add(idx);
                    for (int a = 0; a < 2; a++)
                        for (int b = 0; b < 2; b++)
                            for (int c = 0; c < 2; c++)
                                aNodeId[Wrap(i + a, j + b, k + c)] = 0;
                }

        int nNodes = 0;
        for (int n = 0; n < aNodeId.Length; n++)
            if (aNodeId[n] == 0)
                aNodeId[n] = nNodes++;

        var aNodeX = new float[nNodes];
        var aNodeY = new float[nNodes];
        var aNodeZ = new float[nNodes];
        for (int n = 0; n < aNodeId.Length; n++)
        {
            int id = aNodeId[n];
            if (id < 0) continue;
            aNodeX[id] = n / (ny * nz) * h;
            aNodeY[id] = n / nz % ny * h;
            aNodeZ[id] = n % nz * h;
        }

        int nElem = aElemCells.Count;
        var aElemNodes = new int[nElem * 8];
        var aColourLists = new List<int>[8];
        for (int c = 0; c < 8; c++) aColourLists[c] = [];
        for (int e = 0; e < nElem; e++)
        {
            int idx = aElemCells[e];
            int i = idx / (ny * nz);
            int j = (idx / nz) % ny;
            int k = idx % nz;
            for (int a = 0; a < 2; a++)
                for (int b = 0; b < 2; b++)
                    for (int c = 0; c < 2; c++)
                        aElemNodes[(e * 8) + (a * 4) + (b * 2) + c] = aNodeId[Wrap(i + a, j + b, k + c)];
            aColourLists[((i & 1) * 4) + ((j & 1) * 2) + (k & 1)].Add(e);
        }

        return new Mesh
        {
            ElemNodes = aElemNodes,
            Colours = [.. aColourLists.Select(l => l.ToArray())],
            NodeCount = nNodes,
            NodeX = aNodeX,
            NodeY = aNodeY,
            NodeZ = aNodeZ,
            ElementCount = nElem,
            DiscardedIslandFraction = dDiscarded,
            SolidFraction = dSolidFraction,
            // A period cell has no specimen section; the faces are the cell's own, never read by the periodic case.
            NominalAreaMm2X = ny * (double)h * nz * h,
            NominalAreaMm2Y = nx * (double)h * nz * h,
            NominalAreaMm2Z = nx * (double)h * ny * h,
            ExtentXMm = nx * (double)h,
            ExtentYMm = ny * (double)h,
            ExtentZMm = nz * (double)h,
        };
    }

    // u = E·x at the eight local nodes, x from the element's own corner (h·(a, b, c)), for the k-th unit macro strain in
    // Voigt [xx, yy, zz, yz, zx, xy] with ENGINEERING shear — so a unit shear k ≥ 3 puts ½ in each off-diagonal of E.
    private static double[] UnitStrainNodalDisplacement(int k, double h)
    {
        var aE = new double[3, 3];
        switch (k)
        {
            case 0: aE[0, 0] = 1.0; break;
            case 1: aE[1, 1] = 1.0; break;
            case 2: aE[2, 2] = 1.0; break;
            case 3: aE[1, 2] = aE[2, 1] = 0.5; break;
            case 4: aE[0, 2] = aE[2, 0] = 0.5; break;
            default: aE[0, 1] = aE[1, 0] = 0.5; break;
        }
        var aU = new double[24];
        for (int n = 0; n < 8; n++)
        {
            double[] aX = [h * (s_aCornerXi[n] + 1.0) / 2.0, h * (s_aCornerEta[n] + 1.0) / 2.0, h * (s_aCornerZeta[n] + 1.0) / 2.0];
            for (int i = 0; i < 3; i++)
                aU[(n * 3) + i] = (aE[i, 0] * aX[0]) + (aE[i, 1] * aX[1]) + (aE[i, 2] * aX[2]);
        }
        return aU;
    }

    private static double[] MultiplyElement(double[] aKe, double[] aU)
    {
        var aF = new double[24];
        for (int r = 0; r < 24; r++)
        {
            double dSum = 0.0;
            for (int c = 0; c < 24; c++) dSum += aKe[(r * 24) + c] * aU[c];
            aF[r] = dSum;
        }
        return aF;
    }

    private static double QuadraticForm(double[] aKe, double[] aU)
    {
        double dSum = 0.0;
        for (int r = 0; r < 24; r++)
        {
            double dRow = 0.0;
            for (int c = 0; c < 24; c++) dRow += aKe[(r * 24) + c] * aU[c];
            dSum += aU[r] * dRow;
        }
        return dSum;
    }

    private static void StrainAt(double[] aB, double[] aUe, double[] aEps)
    {
        for (int i = 0; i < 6; i++)
        {
            double dSum = 0.0;
            for (int c = 0; c < 24; c++) dSum += aB[(i * 24) + c] * aUe[c];
            aEps[i] = dSum;
        }
    }

    private static void StressFrom(double[,] aD, double[] aEps, double[] aSig)
    {
        for (int i = 0; i < 6; i++)
        {
            double dSum = 0.0;
            for (int j = 0; j < 6; j++) dSum += aD[i, j] * aEps[j];
            aSig[i] = dSum;
        }
    }

    // The element's total displacement: the macro strain's u0 (the same on every element) plus its fluctuation.
    private static void ElementDisplacement(Mesh mesh, int e, double[] aU0, double[] aFluct, double[] aUe)
    {
        for (int n = 0; n < 8; n++)
        {
            int nd = mesh.ElemNodes[(e * 8) + n] * 3;
            for (int d = 0; d < 3; d++) aUe[(n * 3) + d] = aU0[(n * 3) + d] + aFluct[nd + d];
        }
    }

    // The cell's stress integral Σ_g V_g·D·B_g·u_e (still to be divided by the cell volume) and its strain energy
    // ½·Σ u_eᵀ·Ke·u_e — two different routes to the same work, which is what HillMandelWorst compares.
    private static (double[] SigmaTimesVolume, double Energy) CellIntegrals(
        Mesh mesh, double[] aKe, double[,] aD, double[][] aBg, double[] aU0, double[] aFluct, double dGaussVolume)
    {
        var aSum = new double[6];
        double dEnergy = 0.0;
        var aUe = new double[24];
        var aEps = new double[6];
        var aSig = new double[6];
        for (int e = 0; e < mesh.ElementCount; e++)
        {
            ElementDisplacement(mesh, e, aU0, aFluct, aUe);
            foreach (double[] aB in aBg)
            {
                StrainAt(aB, aUe, aEps);
                StressFrom(aD, aEps, aSig);
                for (int i = 0; i < 6; i++) aSum[i] += aSig[i] * dGaussVolume;
            }
            dEnergy += 0.5 * QuadraticForm(aKe, aUe);
        }
        return (aSum, dEnergy);
    }

    // A unit uniaxial macro stress along (cos θ, sin θ, 0): its macro strain ε̄ = C⁻¹Σ superposes the six solved fields, and
    // the field is read at every Gauss point — the energy, the largest absolute principal stress and von Mises.
    private static UniaxialField UniaxialStressField(
        double dThetaDeg, double[,] aC, Mesh mesh, double[,] aD, double[][] aBg, double[][] aU0, double[][] aFluct,
        double dSolidFraction)
    {
        double dTheta = dThetaDeg * Math.PI / 180.0;
        double dCos = Math.Cos(dTheta), dSin = Math.Sin(dTheta);
        double[] aSigmaMacro = [dCos * dCos, dSin * dSin, 0.0, 0.0, 0.0, dCos * dSin];
        double[] aStrainMacro = SolveDense(aC, aSigmaMacro);
        double dCompliance = 0.0; // Σ·ε̄ = 1/E_dir for a unit stress
        for (int i = 0; i < 6; i++) dCompliance += aSigmaMacro[i] * aStrainMacro[i];

        var aU0Total = new double[24];
        var aFluctTotal = new double[aFluct[0].Length];
        for (int k = 0; k < 6; k++)
        {
            for (int c = 0; c < 24; c++) aU0Total[c] += aStrainMacro[k] * aU0[k][c];
            for (int d = 0; d < aFluctTotal.Length; d++) aFluctTotal[d] += aStrainMacro[k] * aFluct[k][d];
        }

        int nGauss = mesh.ElementCount * aBg.Length;
        var aPrincipal = new double[nGauss];
        var aVonMises = new double[nGauss];
        double dEnergySum = 0.0;
        var aUe = new double[24];
        var aEps = new double[6];
        var aSig = new double[6];
        int g = 0;
        for (int e = 0; e < mesh.ElementCount; e++)
        {
            ElementDisplacement(mesh, e, aU0Total, aFluctTotal, aUe);
            foreach (double[] aB in aBg)
            {
                StrainAt(aB, aUe, aEps);
                StressFrom(aD, aEps, aSig);
                double dW = 0.0;
                for (int i = 0; i < 6; i++) dW += aSig[i] * aEps[i];
                dEnergySum += 0.5 * dW;
                (double dS1, _, double dS3) = PrincipalStresses(aSig);
                aPrincipal[g] = Math.Max(Math.Abs(dS1), Math.Abs(dS3));
                aVonMises[g] = VonMises(aSig);
                g++;
            }
        }

        double dMeanEnergySolid = dEnergySum / nGauss;      // equal Gauss volumes: the mean over the metal
        double dSigmaW = Math.Sqrt(2.0 * dMeanEnergySolid);  // E_s = 1
        int nAbove = aPrincipal.Count(p => p > dSigmaW);
        Array.Sort(aPrincipal);
        Array.Sort(aVonMises);
        return new UniaxialField
        {
            ThetaDeg = dThetaDeg,
            ModulusRatio = 1.0 / dCompliance,
            SigmaWPerMacroStress = dSigmaW,
            EnergyIdentityResidual = Math.Abs((2.0 * dSolidFraction * dMeanEnergySolid / dCompliance) - 1.0),
            PrincipalOverSigmaW = [.. FieldQuantiles.Select(q => Quantile(aPrincipal, q) / dSigmaW)],
            VonMisesOverSigmaW = [.. FieldQuantiles.Select(q => Quantile(aVonMises, q) / dSigmaW)],
            ShareAboveSigmaW = (double)nAbove / nGauss,
        };
    }

    // Nearest-rank quantile of an ascending-sorted sample; q = 1 is the maximum.
    internal static double Quantile(double[] aSorted, double q)
        => aSorted[Math.Clamp((int)Math.Ceiling(q * aSorted.Length) - 1, 0, aSorted.Length - 1)];

    internal static double VonMises(double[] s)
        => Math.Sqrt((0.5 * (((s[0] - s[1]) * (s[0] - s[1])) + ((s[1] - s[2]) * (s[1] - s[2])) + ((s[2] - s[0]) * (s[2] - s[0]))))
                     + (3.0 * ((s[3] * s[3]) + (s[4] * s[4]) + (s[5] * s[5]))));

    // Eigenvalues of a symmetric 3×3 stress (Voigt [xx, yy, zz, yz, zx, xy]), descending — the trigonometric closed form.
    internal static (double S1, double S2, double S3) PrincipalStresses(double[] s)
    {
        double dP1 = (s[3] * s[3]) + (s[4] * s[4]) + (s[5] * s[5]);
        double dQ = (s[0] + s[1] + s[2]) / 3.0;
        double dA = s[0] - dQ, dB = s[1] - dQ, dCc = s[2] - dQ;
        double dP2 = (dA * dA) + (dB * dB) + (dCc * dCc) + (2.0 * dP1);
        if (dP2 <= 0.0)
            return (dQ, dQ, dQ);
        double dP = Math.Sqrt(dP2 / 6.0);
        double b11 = dA / dP, b22 = dB / dP, b33 = dCc / dP, b23 = s[3] / dP, b13 = s[4] / dP, b12 = s[5] / dP;
        double dDet = (b11 * ((b22 * b33) - (b23 * b23))) - (b12 * ((b12 * b33) - (b23 * b13))) + (b13 * ((b12 * b23) - (b22 * b13)));
        double dR = Math.Clamp(dDet / 2.0, -1.0, 1.0);
        double dPhi = Math.Acos(dR) / 3.0;
        double dS1 = dQ + (2.0 * dP * Math.Cos(dPhi));
        double dS3 = dQ + (2.0 * dP * Math.Cos(dPhi + (2.0 * Math.PI / 3.0)));
        return (dS1, (3.0 * dQ) - dS1 - dS3, dS3);
    }

    // C·x = b for a small dense system, Gaussian elimination with partial pivoting; refuses a singular tensor rather than
    // returning a number for a direction the lattice cannot carry.
    internal static double[] SolveDense(double[,] aA, double[] aRhs)
    {
        int n = aRhs.Length;
        var aM = new double[n, n + 1];
        double dScale = 0.0;
        for (int i = 0; i < n; i++)
        {
            for (int j = 0; j < n; j++) { aM[i, j] = aA[i, j]; dScale = Math.Max(dScale, Math.Abs(aA[i, j])); }
            aM[i, n] = aRhs[i];
        }
        for (int col = 0; col < n; col++)
        {
            int nPivot = col;
            for (int r = col + 1; r < n; r++)
                if (Math.Abs(aM[r, col]) > Math.Abs(aM[nPivot, col])) nPivot = r;
            if (Math.Abs(aM[nPivot, col]) <= 1e-12 * dScale)
                throw new InvalidOperationException("the tensor is singular — the lattice carries no stress in some direction");
            if (nPivot != col)
                for (int j = 0; j <= n; j++) (aM[col, j], aM[nPivot, j]) = (aM[nPivot, j], aM[col, j]);
            for (int r = 0; r < n; r++)
            {
                if (r == col) continue;
                double dF = aM[r, col] / aM[col, col];
                for (int j = col; j <= n; j++) aM[r, j] -= dF * aM[col, j];
            }
        }
        var aX = new double[n];
        for (int i = 0; i < n; i++) aX[i] = aM[i, n] / aM[i, i];
        return aX;
    }

    // ── Grid helpers ─────────────────────────────────────────────────────────────────────────────

    /// <summary>Mark every Solid cell in the largest face-connected solid body; report what was dropped.</summary>
    internal static (bool[] Keep, double SolidFraction, double Discarded) LargestSolidBody(in Connectivity.Grid grid)
    {
        bool[] aKeep = Connectivity.LargestComponentMask(grid, Phase.Solid);
        long nSolid = 0, nKeep = 0, nInside = 0;
        for (int n = 0; n < grid.Cells.Length; n++)
        {
            if (grid.Cells[n] == Phase.Outside) continue;
            nInside++;
            if (grid.Cells[n] != Phase.Solid) continue;
            nSolid++;
            if (aKeep[n]) nKeep++;
        }
        return (aKeep,
            nInside > 0 ? (double)nKeep / nInside : 0.0,
            nSolid > 0 ? 1.0 - ((double)nKeep / nSolid) : 0.0);
    }

    /// <summary>The same envelope with every inside cell solid — the self-calibration run.</summary>
    internal static Connectivity.Grid SolidCounterpart(in Connectivity.Grid grid)
    {
        var aCells = new Phase[grid.Cells.Length];
        for (int n = 0; n < grid.Cells.Length; n++)
            aCells[n] = grid.Cells[n] == Phase.Outside ? Phase.Outside : Phase.Solid;
        return new Connectivity.Grid(aCells, grid.Nx, grid.Ny, grid.Nz, grid.StepMm);
    }

    /// <summary>
    /// Sample the anchor for FE on the RENDERED envelope — inner radius = Zone1Anode.InnerRadiusMm, the
    /// surface `build` actually cuts and the same one Connectivity.SampleAnchor clips the topology grid
    /// to, so the FE stands on the geometry the factory would receive and on the grid every topology
    /// metric reads. ⛔ The `bWithRod` override that stood here was REMOVED on 2026-09-18 with the branch it
    /// modelled: the bus rod is no longer printed with the anode (welded wire, ⚖️ 2026-09-10), so forcing a
    /// solid core would measure a body the factory never receives — and canon quoted its «+9 % axial» as a
    /// property of the part. What the wire does to the ASSEMBLY is a beam question and lives in-silico (`55`).
    /// </summary>
    internal static Connectivity.Grid SampleAnchorAsBuilt(IImplicit sdf, AnchorCem cem, float fStepMm)
    {
        float fROuter = cem.OuterDiameterMm / 2f;
        float fRInner = Zone1Anode.InnerRadiusMm(cem);
        return Connectivity.SampleRegion(
            sdf, 2f * fROuter, 2f * fROuter, cem.LengthMm, fStepMm,
            (x, y, _) =>
            {
                float fR = MathF.Sqrt((x * x) + (y * y));
                return fR >= fRInner && fR <= fROuter;
            },
            (_, _, _) => (Phase?)null,
            fXMin: -fROuter, fYMin: -fROuter, fZMin: 0f);
    }

    /// <summary>Least-squares fit of `E/E_solid = C·ρⁿ` in log space (00_07 HW.33).</summary>
    internal readonly record struct PowerLaw
    {
        public required double C { get; init; }
        public required double N { get; init; }
        /// <summary>Coefficient of determination of the LOG-space regression, not of E itself.</summary>
        public required double RSquared { get; init; }
        public required int Points { get; init; }
    }

    /// <summary>
    /// Fit `E/E_solid = C·ρⁿ` to measured (relative density, stiffness ratio) pairs by ordinary least
    /// squares on `ln E = ln C + n·ln ρ`.
    ///
    /// 🔑 WHY A FIT AND NOT A SOLVE: one porosity cannot separate C from n — any C is reachable by
    /// moving n, so a single point pins only their product at that ρ. The canon carried `C ≈ 1`
    /// (01_01 §5.2, uncertainty (3)) purely as an idealisation, and `n ≈ 2` from the textbook
    /// bending-dominated argument; neither was ever measured on OUR lattice.
    ///
    /// ⚠️ DECLARED CEILING. (a) Log-space OLS weights each point equally in ln E, i.e. it minimises
    /// RELATIVE error — appropriate here, and deliberately not the same fit as least-squares on E.
    /// (b) The exponent is a SLOPE, so any bias that is constant in log space lands entirely in C and
    /// leaves n alone — of either sign: the staircase changes the body and no ladder shows its sign
    /// (01_01 §5.2) — but a bias that VARIES with ligament thickness does move n, and ligament thickness is
    /// exactly what the sweep varies. That is why nothing here is quoted from one resolution: run the
    /// same sweep at two steps-per-period and read the spread as the instrument's own uncertainty.
    /// (c) R² is reported on the log regression; a high value says the power law describes the points,
    /// never that the points describe the printed part.
    /// </summary>
    internal static PowerLaw FitPowerLaw(IReadOnlyList<(double Density, double Ratio)> aPoints)
    {
        if (aPoints.Count < 2)
            throw new ArgumentException("a power law needs at least two points to separate C from n", nameof(aPoints));
        if (aPoints.Any(p => p.Density <= 0.0 || p.Ratio <= 0.0))
            throw new ArgumentException("density and stiffness ratio must be positive to take a log", nameof(aPoints));

        int n = aPoints.Count;
        double dSx = 0.0, dSy = 0.0;
        foreach ((double dRho, double dE) in aPoints)
        {
            dSx += Math.Log(dRho);
            dSy += Math.Log(dE);
        }
        double dMx = dSx / n, dMy = dSy / n;

        double dSxx = 0.0, dSxy = 0.0;
        foreach ((double dRho, double dE) in aPoints)
        {
            double dX = Math.Log(dRho) - dMx;
            dSxx += dX * dX;
            dSxy += dX * (Math.Log(dE) - dMy);
        }
        if (dSxx <= 0.0)
            throw new ArgumentException("every point has the same density — the sweep varied nothing", nameof(aPoints));

        double dSlope = dSxy / dSxx;
        double dIntercept = dMy - (dSlope * dMx);

        double dSsRes = 0.0, dSsTot = 0.0;
        foreach ((double dRho, double dE) in aPoints)
        {
            double dPred = dIntercept + (dSlope * Math.Log(dRho));
            double dObs = Math.Log(dE);
            dSsRes += (dObs - dPred) * (dObs - dPred);
            dSsTot += (dObs - dMy) * (dObs - dMy);
        }

        return new PowerLaw
        {
            C = Math.Exp(dIntercept),
            N = dSlope,
            RSquared = dSsTot > 0.0 ? 1.0 - (dSsRes / dSsTot) : 1.0,
            Points = n,
        };
    }

    /// <summary>
    /// A plain cube of the same lattice, `nCells` periods on a side — the MATERIAL-scale counterpart
    /// of the part. Running the axial case over a ladder of nCells is how the size effect is measured
    /// rather than argued: the part's radial wall spans 1.5–2.5 cells (01_01 §5.2), so the gap between
    /// the ladder's converged value and its low-n rungs IS the correction Gibson-Ashby cannot give.
    /// </summary>
    internal static Connectivity.Grid SampleLatticeCube(
        float fPeriodMm, float fWallParam, bool bNetwork, int nCells, int nStepsPerPeriod)
    {
        float fExtent = nCells * fPeriodMm;
        float fStep = fPeriodMm / nStepsPerPeriod;
        IImplicit oField = new GradedCartesianGyroid(
            0f, 0f, fPeriodMm, fPeriodMm, fWallParam, fWallParam, bNetwork, fPeriodAxialMm: fPeriodMm);
        return Connectivity.SampleRegion(
            oField, fExtent, fExtent, fExtent, fStep,
            static (_, _, _) => true, static (_, _, _) => (Phase?)null, 0f, 0f, 0f);
    }
}
