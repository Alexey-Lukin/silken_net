// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;

namespace SilkenCad;

// Voxel finite-element homogenisation of the Zone-1 lattice (00_07 HW.51 / HW.33).
//
// 🔴 WHY THIS EXISTS, in one sentence: the only stiffness number the canon has for this part comes
// from Gibson-Ashby `E_foam/E_solid ≈ C·ρⁿ`, and the shipped SKUs sit OUTSIDE that relation's domain
// of validity — 1.50–2.50 cells across the radial wall (01_01 §5.2, uncertainty (4)) — so 13.6 GPa is
// the value of a formula evaluated where the formula does not apply, not a prediction for this
// geometry. This module measures the APPARENT stiffness of the real part instead.
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
//   • Staircase boundaries. A voxel mesh cannot represent an inclined ligament surface; fully
//     integrated trilinear hexes are additionally too stiff in bending, and a NETWORK gyroid is
//     bending-dominated. Both errors push the same way, so a single-resolution number is an UPPER
//     bound — which is why every result carries a step sweep and nothing is quoted without one.
//   • It measures the part as MODELLED, i.e. the geometric intent. As-printed thickening is a
//     separate input (`dilateVoxels`), not a correction folded in silently.
//   • The ratio is to the solid ENVELOPE, so it already contains the free-surface size effect of the
//     real annular wall. That is the point; it is NOT a material property and must not be quoted as one.
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
    internal static double[] HexElementStiffness(double dSideMm, double dNu)
    {
        // Corner signs in local order a*4 + b*2 + c with (a,b,c) ∈ {0,1}³ → (ξ,η,ζ) = (2a−1, 2b−1, 2c−1).
        var aXi = new double[8];
        var aEta = new double[8];
        var aZeta = new double[8];
        for (int a = 0; a < 2; a++)
            for (int b = 0; b < 2; b++)
                for (int c = 0; c < 2; c++)
                {
                    int n = (a * 4) + (b * 2) + c;
                    aXi[n] = (2 * a) - 1;
                    aEta[n] = (2 * b) - 1;
                    aZeta[n] = (2 * c) - 1;
                }

        double dLambda = dNu / ((1.0 + dNu) * (1.0 - (2.0 * dNu)));
        double dMu = 1.0 / (2.0 * (1.0 + dNu));
        // Voigt order [xx, yy, zz, yz, zx, xy]; the shear rows carry engineering strain, hence μ not 2μ.
        var aD = new double[6, 6];
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++)
                aD[i, j] = dLambda + (i == j ? 2.0 * dMu : 0.0);
        for (int i = 3; i < 6; i++)
            aD[i, i] = dMu;

        double dG = 1.0 / Math.Sqrt(3.0);
        double[] aGauss = [-dG, dG];
        double dDetJ = (dSideMm / 2.0) * (dSideMm / 2.0) * (dSideMm / 2.0);
        double dScale = 2.0 / dSideMm; // d/dx = (2/h) d/dξ

        var aK = new double[24 * 24];
        var aB = new double[6 * 24];

        foreach (double dXi in aGauss)
            foreach (double dEta in aGauss)
                foreach (double dZeta in aGauss)
                {
                    Array.Clear(aB);
                    for (int n = 0; n < 8; n++)
                    {
                        double dNdx = 0.125 * aXi[n] * (1 + (dEta * aEta[n])) * (1 + (dZeta * aZeta[n])) * dScale;
                        double dNdy = 0.125 * aEta[n] * (1 + (dXi * aXi[n])) * (1 + (dZeta * aZeta[n])) * dScale;
                        double dNdz = 0.125 * aZeta[n] * (1 + (dXi * aXi[n])) * (1 + (dEta * aEta[n])) * dScale;
                        int ix = (3 * n) + 0, iy = (3 * n) + 1, iz = (3 * n) + 2;
                        aB[(0 * 24) + ix] = dNdx;
                        aB[(1 * 24) + iy] = dNdy;
                        aB[(2 * 24) + iz] = dNdz;
                        aB[(3 * 24) + iy] = dNdz; aB[(3 * 24) + iz] = dNdy; // γ_yz
                        aB[(4 * 24) + ix] = dNdz; aB[(4 * 24) + iz] = dNdx; // γ_zx
                        aB[(5 * 24) + ix] = dNdy; aB[(5 * 24) + iy] = dNdx; // γ_xy
                    }

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
    // leaves the free subspace and no artificial stiffness is introduced.
    private static (double[] U, int Iterations, double Residual, bool Converged) Solve(
        System_ sys, double dTol, int nMaxIter)
    {
        int nDof = sys.Mesh.NodeCount * 3;
        var aUc = new double[nDof];
        for (int d = 0; d < nDof; d++)
            if (sys.Fixed[d]) aUc[d] = sys.Prescribed[d];

        var aTmp = new double[nDof];
        Multiply(sys, aUc, aTmp);
        var aB = new double[nDof];
        for (int d = 0; d < nDof; d++)
            aB[d] = sys.Fixed[d] ? 0.0 : -aTmp[d];

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

    /// <summary>
    /// Radial stiffness of the annulus: a uniform inward radial displacement is imposed on the outer
    /// boundary shell, the two end faces are held in the axial direction (plane-strain surrogate for
    /// a part much longer than its wall), and the inward reaction is summed. Reported as an average
    /// radial pressure divided by diametral strain, in units of E_solid — the SAME test on the solid
    /// envelope is the normaliser, so no thick-cylinder inversion is needed and none is assumed.
    /// This is the load the press-fit and the tree's own swelling apply (01_01 §4.2).
    /// </summary>
    internal static FeaResult RadialStiffness(
        in Connectivity.Grid grid, double dOuterRadiusMm, double dTol = 1e-8, int nMaxIter = 200_000)
    {
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
    /// Sample the anchor for FE on the RENDERED envelope — inner radius = the monolithic bus-rod
    /// surface (Zone1Anode.InnerRadiusMm), which is what `build` actually cuts. ⚠️ Connectivity's own
    /// SampleAnchor uses the CEM `bore_diameter_mm` instead, so the two envelopes differ on a part
    /// that carries a rod; the FE must stand on the geometry the factory would receive.
    /// `bWithRod` adds the solid core, turning "the lattice annulus" into "the part as printed".
    /// </summary>
    internal static Connectivity.Grid SampleAnchorAsBuilt(
        IImplicit sdf, AnchorCem cem, float fStepMm, bool bWithRod)
    {
        float fROuter = cem.OuterDiameterMm / 2f;
        float fRInner = Zone1Anode.InnerRadiusMm(cem);
        return Connectivity.SampleRegion(
            sdf, 2f * fROuter, 2f * fROuter, cem.LengthMm, fStepMm,
            (x, y, _) =>
            {
                float fR = MathF.Sqrt((x * x) + (y * y));
                return bWithRod ? fR <= fROuter : fR >= fRInner && fR <= fROuter;
            },
            (x, y, _) =>
            {
                if (!bWithRod) return (Phase?)null;
                float fR = MathF.Sqrt((x * x) + (y * y));
                return fR < fRInner ? Phase.Solid : null; // the rod is SDF-invisible; force it solid
            },
            fXMin: -fROuter, fYMin: -fROuter, fZMin: 0f);
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
            0f, 0f, fPeriodMm, fPeriodMm, fWallParam, fWallParam, bNetwork);
        return Connectivity.SampleRegion(
            oField, fExtent, fExtent, fExtent, fStep,
            static (_, _, _) => true, static (_, _, _) => (Phase?)null, 0f, 0f, 0f);
    }
}
