// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// ISO 13314 compression coupon (canon 01_01 §5.2 (в), 00_07 HW.33): a cylinder of the anode's own lattice at one
// constant period. Deliberately thin — it owns the coupon's SHAPE (a cylinder, optionally longer by the cut stock)
// and nothing of the lattice: field, envelope clip, porosity and connectivity all go through `Zone1Anode` on the
// record `Lattice` returns, so the coupon and the anode cannot drift into two gyroid implementations.
internal static class CompressionCoupon
{
    // ISO 13314:2011 §6.1, as read into canon 01_01 §5.2 (1): height over diameter between 1 and 2, every dimension
    // at least 10 mm. Mirrors of that canon paragraph — edit THERE first. The standard's third clause (every
    // dimension ≥ 10 mean pore sizes) needs a pore-size convention canon gives two of, so it is REPORTED as cells
    // per dimension (`CellsAcross`), never gated here.
    internal const float AspectMin = 1f, AspectMax = 2f, MinDimensionMm = 10f;

    // The anode-equivalent record: the same lattice the anode generator builds, with BOTH periods the coupon's one
    // (no gradient), no bus wire, and the FINISHED length — what `verify` measures is the specimen that is tested,
    // whatever stock the print carries. ⛔ Topology is validated here because `Zone1Anode.Gyroid` reads anything
    // that is not "network" or "stepped" as sheet — a typo would build the other branch without a word.
    internal static AnchorCem Lattice(CompressionCouponCem cem)
    {
        if (cem.Topology is not ("network" or "sheet"))
            throw new InvalidDataException(
                $"compression_coupon '{cem.Name}': topology '{cem.Topology}' — a constant-period coupon is 'network' or 'sheet' " +
                "(a zoned 'stepped' lattice has no single period to test)");
        if (cem.EdmEndStockMm is <= 0f)
            throw new InvalidDataException(
                $"compression_coupon '{cem.Name}': edm_end_stock_mm = {cem.EdmEndStockMm} — omit the field until the vendor " +
                "states the stock; a zero or negative one is not a way to say 'none'");
        return new AnchorCem
        {
            Name = cem.Name,
            VoxelSizeMm = cem.VoxelSizeMm,
            OuterDiameterMm = cem.DiameterMm,
            LengthMm = cem.LengthMm,
            GyroidPeriodMm = cem.GyroidPeriodMm,
            GyroidPeriodRimMm = cem.GyroidPeriodMm,
            GyroidWallParam = cem.GyroidWallParam,
            Topology = cem.Topology,
            PorosityTarget = cem.PorosityTarget,
            SlmMinWallMm = cem.SlmMinWallMm,
        };
    }

    // The body the printer receives, in the SPECIMEN's frame: the cut planes are z = 0 and z = LengthMm, the stock
    // (if the manifest carries one) lies outside them — so the lattice between the cuts is the very one `verify`
    // measured, not a copy shifted by the stock. Without stock this is `Zone1Anode.Build` of the finished cylinder.
    internal static float PrintedLengthMm(CompressionCouponCem cem) => cem.LengthMm + (2f * (cem.EdmEndStockMm ?? 0f));
    internal static float PrintedZMinMm(CompressionCouponCem cem) => 0f - (cem.EdmEndStockMm ?? 0f);   // 0 − 0, never a printed «-0»

    public static Voxels Build(CompressionCouponCem cem)
    {
        AnchorCem lattice = Lattice(cem);
        if (cem.EdmEndStockMm is null)
            return Zone1Anode.Build(lattice);
        BasePipe oBody = new(new LocalFrame(new Vector3(0f, 0f, PrintedZMinMm(cem))), PrintedLengthMm(cem),
                             Zone1Anode.InnerRadiusMm(lattice), cem.DiameterMm / 2f);
        return Zone1Anode.Anode(lattice, oBody.voxConstruct());
    }

    internal static float AspectRatio(CompressionCouponCem cem) => cem.LengthMm / cem.DiameterMm;

    // Unit cells across the diameter and along the tested height — what the stricter reading of the standard counts
    // (canon 01_01 §5.2 (г): «at least 10 unit cells»).
    internal static (float Diameter, float Height) CellsAcross(CompressionCouponCem cem)
        => (cem.DiameterMm / cem.GyroidPeriodMm, cem.LengthMm / cem.GyroidPeriodMm);

    // What the standard's specimen window refuses, on the FINISHED dimensions; empty = inside the window.
    internal static IReadOnlyList<string> SpecimenFindings(CompressionCouponCem cem)
    {
        var a = new List<string>();
        float fAspect = AspectRatio(cem);
        if (fAspect < AspectMin || fAspect > AspectMax)
            a.Add($"height/diameter {fAspect:0.##} is outside {AspectMin:0}–{AspectMax:0} (ISO 13314 §6.1)");
        if (cem.DiameterMm < MinDimensionMm)
            a.Add($"diameter {cem.DiameterMm:0.##} mm is below {MinDimensionMm:0} mm (ISO 13314 §6.1)");
        if (cem.LengthMm < MinDimensionMm)
            a.Add($"height {cem.LengthMm:0.##} mm is below {MinDimensionMm:0} mm (ISO 13314 §6.1)");
        return a;
    }
}
