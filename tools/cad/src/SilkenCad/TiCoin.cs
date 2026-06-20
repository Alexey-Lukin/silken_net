using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Flat Ti-coin coupon (Stage-2 in-vitro CV, 01_01 §6.1) with an integral
// suspension eyelet (вушко) for hanging in the electrochemistry cell. Disc + torus
// loop fused with BoolAdd; a torus carries its own through-hole, so no separate
// subtraction is needed. Deliberately trivial — this is the toolchain smoke-test
// part (no sub-100 µm features → does not stress voxel memory).
internal static class TiCoin
{
    public static Voxels Build(TiCoinCem cem)
    {
        float fDiscR = cem.DiscDiameterMm / 2f;

        // Disc: a thin cylinder along the frame's Z, spanning Z in [0, thickness].
        BaseCylinder oDisc = new(new LocalFrame(), cem.DiscThicknessMm, fDiscR);
        Voxels voxCoin = oDisc.voxConstruct();

        // Eyelet torus, coplanar with the disc mid-plane, overlapping the rim by one
        // tube radius so the union fuses without a sliver.
        float fEyeletX = fDiscR + cem.LoopRingRadiusMm - cem.LoopTubeRadiusMm;
        LocalFrame oFrame = new(new Vector3(fEyeletX, 0f, cem.DiscThicknessMm / 2f));
        BaseRing oLoop = new(oFrame, cem.LoopRingRadiusMm, cem.LoopTubeRadiusMm);

        voxCoin.BoolAdd(oLoop.voxConstruct());
        return voxCoin;
    }
}
