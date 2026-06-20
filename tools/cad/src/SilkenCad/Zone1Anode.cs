using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Cartesian gyroid SDF (bicontinuous, isotropic period) — uniform everywhere (no axis
// singularity, unlike LatticeLibrary's radial ImplicitRadialGyroid near r=0). Still
// bicontinuous, the orientation-agnostic property the founder's decision (б) accepted
// (HW.33). Formula matches the LEAP presets exactly: |eq| − 0.5*wallParam (dimensionless;
// solid where < 0). Per the LEAP guide, a clean wall needs wallParam ≪ the eq amplitude.
internal sealed class CartesianGyroid(float fPeriodMm, float fWallParam) : IImplicit
{
    private readonly float _fFreq = 2f * MathF.PI / fPeriodMm;

    public float fSignedDistance(in Vector3 vecPt)
    {
        float fX = _fFreq * vecPt.X, fY = _fFreq * vecPt.Y, fZ = _fFreq * vecPt.Z;
        double dEq = (Math.Sin(fX) * Math.Cos(fY)) + (Math.Sin(fY) * Math.Cos(fZ)) + (Math.Sin(fZ) * Math.Cos(fX));
        return (float)(Math.Abs(dEq) - (0.5f * fWallParam));
    }
}

// Zone-1 gyroid anode (01_01 §5): a gyroid Ti rod (Ø per CEM, founder Ø11) with a
// central bore for the bus conductor, clipped from a BasePipe envelope. Bicontinuous,
// orientation-agnostic (founder decision (б), HW.33). v1 = CONSTANT period; the radial
// pore gradient (300→100µm) is v2 via spatial modulation. Barbs (01_01 §4.3A) also v2.
internal static class Zone1Anode
{
    // Solid pipe envelope (outer Ø + central bore) — also the porosity reference volume.
    public static Voxels Envelope(AnchorCem cem)
    {
        BasePipe oPipe = new(new LocalFrame(), cem.LengthMm, cem.BoreDiameterMm / 2f, cem.OuterDiameterMm / 2f);
        return oPipe.voxConstruct();
    }

    public static IImplicit Gyroid(AnchorCem cem)
        => new CartesianGyroid(cem.GyroidPeriodMm, cem.GyroidWallParam);

    // Render the gyroid into the envelope's bbox via the Voxels(IImplicit, BBox3) ctor,
    // then BoolIntersect to clip to the pipe. The envelope is left intact (BoolIntersect
    // mutates the gyroid grid) so it can serve as the porosity reference volume.
    public static Voxels Anode(AnchorCem cem, Voxels voxEnvelope)
    {
        Voxels voxGyroid = new(Gyroid(cem), voxEnvelope.oCalculateBoundingBox());
        voxGyroid.BoolIntersect(voxEnvelope);
        return voxGyroid;
    }

    public static Voxels Build(AnchorCem cem) => Anode(cem, Envelope(cem));
}
