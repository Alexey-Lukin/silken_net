// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Falsifiable probes of what we BELIEVE about the PicoGK kernel — not about our geometry.
//
// ⛔ Why this is a permanent verb and not a throwaway script: two of our own hard-won gotchas
// (picogk #1 «uncatchable abort at fine voxel on thin bored parts» and #9 «the SDF ctor renders a
// solid as a hollow shell») record a MECHANISM, and a 2026-09-12 reading of the runtime says both
// mechanisms are wrong while both CONCLUSIONS may stand. A belief about someone else's kernel that
// nothing re-runs is a belief that silently survives their next release. These probes state what
// they expect BEFORE measuring, so the answer is a verdict either way.
//
// ⚠️ Probe B can KILL the process (that is the point — the abort under test is a native one, not a
// .NET exception), so A runs first and every line is flushed as it is printed.
internal static class Probe
{
    // A buried cylinder: max(r − R, |z − zc| − L/2). CLOSED on every side inside the bbox, unlike a
    // bare radial field which stays «inside» at the bbox caps.
    private sealed class BuriedCylinder(float fRadiusMm, float fLengthMm) : IImplicit
    {
        public float fSignedDistance(in Vector3 vecPt)
        {
            float fR = MathF.Sqrt((vecPt.X * vecPt.X) + (vecPt.Y * vecPt.Y)) - fRadiusMm;
            float fZ = MathF.Abs(vecPt.Z - (fLengthMm / 2f)) - (fLengthMm / 2f);
            return MathF.Max(fR, fZ);
        }
    }

    public static int Run(float fVoxelMm)
    {
        Console.WriteLine($"probe — PicoGK kernel assumptions at voxel {fVoxelMm:F3} mm");
        Console.WriteLine();

        // ── A. gotcha #9: does the SDF ctor render a CLOSED solid as solid? ──────────────────────
        // Our rule says «a FILLED body must come from voxConstruct, NOT new Voxels(IImplicit, BBox3)»,
        // and its stated mechanism is the narrow band. The competing claim: the band is fine, and the
        // shell we once measured came from a field left OPEN at the bbox caps. A closed field
        // discriminates: if the band were the cause, this too renders hollow.
        const float R = 5.5f, L = 20.0f;
        double dExpected = Math.PI * R * R * L;
        BBox3 oBox = new(new Vector3(-R - 1f, -R - 1f, -1f), new Vector3(R + 1f, R + 1f, L + 1f));
        Voxels voxCyl = new(new BuriedCylinder(R, L), oBox);
        voxCyl.CalculateProperties(out float fVol, out _);
        double dRatio = fVol / dExpected;
        Console.WriteLine($"  A · closed SDF solid (Ø{2 * R:F1} × {L:F0} mm) via the IImplicit ctor:");
        Console.WriteLine($"      rendered {fVol:F1} mm³ vs analytic {dExpected:F1} mm³ → {dRatio:P1}");
        Console.WriteLine(dRatio > 0.9
            ? "      ⇒ SOLID. The ctor does NOT hollow a closed field — gotcha #9's MECHANISM is wrong;\n" +
              "        what hollows a body is a field left open at the bbox, not the narrow band."
            : "      ⇒ HOLLOW. gotcha #9 stands as written: the narrow band itself is the cause.");
        Console.Out.Flush();

        // ── B. gotcha #1: is the fine-voxel abort an int truncation of the narrow band? ──────────
        // Claim under test: the convenience path passes the band WIDTH IN MM into an int parameter,
        // so below 1/3 mm it truncates to 0 and the grid is born invalid. If true the boundary is
        // sharp and arithmetic, not a property of thin geometry: fine at 0.34, fatal at 0.33.
        Console.WriteLine();
        Console.WriteLine($"  B · voxIntersectImplicit at this voxel (3 × {fVoxelMm:F3} = {3 * fVoxelMm:F3}" +
                          $" → int {(int)(3 * fVoxelMm)}):");
        Console.WriteLine(3 * fVoxelMm < 1.0f
            ? "      PREDICTION: the band truncates to 0 → native abort (process dies, no .NET exception)."
            : "      PREDICTION: the band is ≥ 1 → survives.");
        Console.Out.Flush();

        Voxels voxEnvelope = new BasePipe(new LocalFrame(), L, R - 2f, R).voxConstruct();
        Voxels voxOut = voxEnvelope.voxIntersectImplicit(new BuriedCylinder(R - 1f, L));
        voxOut.CalculateProperties(out float fVol2, out _);
        Console.WriteLine($"      SURVIVED — {fVol2:F1} mm³.");
        Console.Out.Flush();
        return 0;
    }
}
