// SPDX-License-Identifier: AGPL-3.0-or-later
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

        // Eyelet torus, coplanar with the disc mid-plane.
        LocalFrame oFrame = new(new Vector3(EyeletCentreFromAxisMm(cem), 0f, cem.DiscThicknessMm / 2f));
        BaseRing oLoop = new(oFrame, cem.LoopRingRadiusMm, cem.LoopTubeRadiusMm);

        voxCoin.BoolAdd(oLoop.voxConstruct());
        return voxCoin;
    }

    // Distance from the disc axis to the eyelet centre: the torus overlaps the rim by one tube radius so the
    // union fuses without a sliver. ⛔ ONE function for the body and for both drawing readers — a sheet that
    // recomputes it draws a loop the STL does not have (00_07 HW.24).
    internal static float EyeletCentreFromAxisMm(TiCoinCem cem)
        => cem.DiscDiameterMm / 2f + cem.LoopRingRadiusMm - cem.LoopTubeRadiusMm;
}
