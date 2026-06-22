using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Full anchor AXIAL stack (Zone 1 anode → Zone 2 PEEK sleeve → Zone 3 flange → Zone 4 radome, 01_01
// §1 + §3 — Заводська Збірка). The SECOND integration artifact after the capsule-end Assembly: every
// part (and the capsule mate) is verified, but nothing yet proved the PRESS-FIT axis Zone-1↔Zone-2↔
// Zone-3 mates. This brings the whole anchor into one frame along its axis and MEASURES the residual
// press-fit mismatch. Like Assembly it is an AUDIT table, not a part pass/fail — the findings are the
// real un-reconciled state (the Zone-3 shank Ø is a HW.8 placeholder), surfaced as ⚠ + asserted by the
// pure xUnit suite, so `verify` exits on a broken render only and CI stays green.
//
// Z-datum = tree-side at z=0 (anode bottom) → capsule-side up. Reuses the per-part generators wholesale:
// the Zone-1 ENVELOPE (solid Ø11 rod — a press-fit cares about the OD, not the gyroid porosity, and it
// keeps the 0.2 mm stack voxel safe) + Zone2Sleeve + the existing Assembly (flange+radome capsule).
internal static class AxialStack
{
    // ── Pure-math mate analysis (CEM-only, no render → xUnit) ──

    // Radial press-fit interference at an interface = (shaft Ø − bore Ø)/2. >0 ⇒ interference (true
    // press-fit); ≤0 ⇒ CLEARANCE (a gap, no grip). Zone-1 shaft Ø11 into the sleeve bore Ø11 ⇒ ~0
    // (nominal line-to-line; the real +interference is the H7/s6 tolerance band, bench — 01_01 §3).
    public static float Zone1SleeveInterferenceMm(AnchorAxialStackCem cem)
        => (cem.Zone1.OuterDiameterMm - cem.Zone2.BoreDiameterMm) / 2f;

    // Zone-3 flange shank into the SAME sleeve bore. Shank Ø9 (placeholder) ↔ bore Ø11 ⇒ −1.0 mm =
    // 1 mm radial CLEARANCE per side → NO press-fit (F1, the key finding → HW.8 shank-Ø reconcile).
    public static float SleeveZone3InterferenceMm(AnchorAxialStackCem cem)
        => (cem.Capsule.Flange.ShankDiameterMm - cem.Zone2.BoreDiameterMm) / 2f;

    // Insertion budget inside the 50 mm bore: the Zone-1 shaft enters one end by Zone1InsertionMm, the
    // Zone-3 shank the other by its shank length. <0 ⇒ they collide inside the sleeve (F2). 01_01 §3/§4.1.
    public static float InsertionBudgetMm(AnchorAxialStackCem cem)
        => cem.Zone2.LengthMm - (cem.Zone1InsertionMm + cem.Capsule.Flange.ShankLengthMm);

    // Sleeve lower-end Z in the stack frame (Zone-1 top, minus how deep the anode inserts).
    public static float SleeveBottomZMm(AnchorAxialStackCem cem)
        => cem.Zone1.LengthMm - cem.Zone1InsertionMm;

    public static float SleeveTopZMm(AnchorAxialStackCem cem)
        => SleeveBottomZMm(cem) + cem.Zone2.LengthMm;

    // Capsule lift so the flange shank inserts into the sleeve's top end by its shank length.
    public static float CapsuleLiftZMm(AnchorAxialStackCem cem)
        => SleeveTopZMm(cem) - cem.Capsule.Flange.ShankLengthMm;

    // Embedded span: anode bottom (z=0) → flange disc top (the bark line + flange shoulder). The radome
    // bayonets ABOVE this (capsule side, over the bark) — F3 install-depth / DBH (CODIT, 01_04 §3).
    public static float OverallStackLengthMm(AnchorAxialStackCem cem)
        => SleeveTopZMm(cem) + cem.Capsule.Flange.FlangeThicknessMm;

    // F3 — the monolithic bus rod (01_01 §1.4) must clear the cathode channel WITH its insulation liner:
    // rod Ø + 2·liner ≤ flange channel Ø. Back-compat: a legacy hollow-bore CEM (rod==0) falls back to the
    // old "anode bore ≥ flange bore" continuity check. Pure boolean finding (CEM-only → xUnit).
    public static bool BusRodClears(AnchorAxialStackCem cem)
        => cem.Zone1.BusRodDiameterMm > 0f
            ? cem.Zone1.BusRodDiameterMm + (2f * cem.Capsule.Flange.BusLinerThicknessMm) <= cem.Capsule.Flange.BoreDiameterMm
            : cem.Zone1.BoreDiameterMm >= cem.Capsule.Flange.BoreDiameterMm;

    // ── Render: bring all zones into the stack frame for the merged STL + interference measurement ──
    public static AxialStackVoxels Build(AnchorAxialStackCem cem)
    {
        // Zone-1 ENVELOPE (solid Ø11 rod; the monolithic bus is the solid core, not a bore) — OD is what press-fits; porosity lives
        // in anchor_zone1. Built z∈[0, LengthMm] from the origin frame (BasePipe, as Zone1Anode.Envelope).
        Voxels voxZone1 = Zone1Anode.Envelope(cem.Zone1);

        // Zone-2 sleeve lifted so its bore overlaps the Zone-1 top end by Zone1InsertionMm.
        float fZ2Bot = SleeveBottomZMm(cem);
        Voxels voxZone2 = MeshUtility.voxApplyTransformation(
            Zone2Sleeve.Build(cem.Zone2), v => v + new Vector3(0f, 0f, fZ2Bot));

        // Zone-3 + Zone-4 capsule (reuse the capsule-end assembly) lifted so the flange shank inserts
        // into the sleeve's top end. The per-part Build stays untouched — vertex-translate, as Assembly.
        float fCapsuleLift = CapsuleLiftZMm(cem);
        Voxels voxCapsule = MeshUtility.voxApplyTransformation(
            Assembly.Build(cem.Capsule).Merged, v => v + new Vector3(0f, 0f, fCapsuleLift));

        Voxels voxMerged = new(voxZone1);
        voxMerged.BoolAdd(voxZone2);
        voxMerged.BoolAdd(voxCapsule);

        // The FULL monolithic bus rod (01_01 §1.4): a Ø(bus) core from the anode bottom (z=0) up through
        // the PEEK gap + the cathode channel to the flange-top pogo pad — the actual anode V−/GND path to
        // the capsule. It is the solid core inside the Ø11 anode, then a free rod threading the cathode
        // channel (Ø1.3, isolated by the liner). voxConstruct (gotcha #9). Kept apart for the section colour.
        Voxels? voxBus = null;
        if (cem.Zone1.BusRodDiameterMm > 0f)
        {
            voxBus = new BaseCylinder(new LocalFrame(), OverallStackLengthMm(cem), cem.Zone1.BusRodDiameterMm / 2f).voxConstruct();
            voxMerged.BoolAdd(voxBus);
        }
        return new AxialStackVoxels(voxMerged, voxZone1, voxZone2, voxCapsule, voxBus);
    }
}

// The assembled stack + the three transformed parts (kept apart for the render overlap measures). At
// the frozen nominal dims these read counter-intuitively, and the audit is HONEST about why: Zone1∩Zone2
// = 0 (anode Ø11 and bore Ø11 are line-to-line → surfaces TOUCH but volumes don't overlap; real press-fit
// is +interference on the bench); sleeve∩capsule ≈ a thin shell = the flange SHOULDER (Ø25 disc) resting
// on the sleeve TOP face (Ø15), NOT the shank — the shank Ø9 floats free in the bore Ø11 (the F1 clearance).
internal sealed record AxialStackVoxels(Voxels Merged, Voxels Zone1, Voxels Zone2, Voxels Capsule, Voxels? Bus = null);
