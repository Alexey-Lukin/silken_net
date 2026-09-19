// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Capsule-end anchor assembly (Деталь 3 ↔ Деталь 4, 02_02 §4 — Механізм Фіксації Капсули). The first
// INTEGRATION artifact of the CAD family: every part is verified in isolation, but nothing yet proved
// they MATE. This brings the cathode flange and the PEEK radome into ONE coordinate frame at the
// bayonet-closed datum (the radome lock-groove aligned to the flange lugs) and MEASURES the residual
// mismatch. It is an AUDIT table, not a pass/fail part: the mismatches it finds are the real state of
// the (still un-reconciled) Z-stack, not a code bug — so `verify` exits on a broken render only, and the
// numeric findings are asserted by the pure xUnit suite (regression) + surfaced as ⚠ for HW.17 / HW.8.
//
// The mate maths is CEM-only (no render) → the xUnit + report surface; the render path is just for the
// merged STL + the flange∩radome interference volume.
internal static class Assembly
{
    // ── Pure-math mate analysis (CEM-only, no render) ──

    // Flange bayonet-lug Z (CathodeFlange.cs: shankLen + thickness/2).
    public static float FlangeLugZMm(AnchorAssemblyCem cem)
        => cem.Flange.ShankLengthMm + (cem.Flange.FlangeThicknessMm / 2f);

    // Flange capsule-side (top / O-ring) face Z.
    public static float FlangeTopZMm(AnchorAssemblyCem cem)
        => cem.Flange.ShankLengthMm + cem.Flange.FlangeThicknessMm;

    // Lug-tip radius (CathodeFlange.cs: base at flangeR−overlap, length protrusion+overlap, overlap 1.0
    // ⇒ tip = flangeR + protrusion). The Ø that the radome socket must clear.
    public static float LugTipRadiusMm(AnchorAssemblyCem cem)
        => (cem.Flange.FlangeDiameterMm / 2f) + cem.Flange.LugProtrusionMm;

    // Radome lift in the flange frame so the radome lock-groove sits at the flange lugs (bayonet datum).
    public static float RadomeLiftZMm(AnchorAssemblyCem cem)
        => FlangeLugZMm(cem) - cem.Radome.LockGrooveZMm;

    // Bayonet-Z mismatch: at the bayonet datum the radome rim lands at `lift`; the seal wants it ON the flange
    // top face. ⚖️ Under branch (а) (2026-09-10, applied 2026-09-14) the rim is a HARD DATUM on that face and
    // the O-ring squeeze is the flange groove's own depth, so the face gap this used to add (`ORingGapMm`,
    // 1.424 = CS·(1 − 0.20), a script-52 mirror) is ZERO by construction and the field is gone — said out loud
    // here and in 02_02 §4.4, not recomputed silently: the mismatch fell 6.42 → 5.0 because a TERM left the
    // chain, not because a value moved.
    //
    // 🔑 SUBSTITUTE AND THE SHANK CANCELS HERE TOO — and what is left is a SUM OF TWO POSITIVE TERMS:
    //     |(shank + t/2 − lockGrooveZ) − (shank + t)| = t/2 + lockGrooveZ
    // So this mismatch has NO ZERO in the current parametrisation, and that is a statement about the
    // PARAMETRISATION, not about the chosen values: shank length is not a lever, and the groove would have
    // to sit above the rim (negative) to close it on its own. The term never derived from the mate is the
    // LUG Z — it is `shank + t/2`, i.e. the middle of the disc, while the seal lands on the TOP face, so
    // the bayonet grips one side of the flange and the seal the other. Closing it needs a lug Z of its own
    // (`RequiredLugZMm` below): the lug stands lockGrooveZ ABOVE the sealing face, not at it — a raised
    // collar, i.e. NEW GEOMETRY, unreachable by re-assigning a frozen dim.
    // ⊕ And the two "independent" equations are tied by an identity, Rf + mismatch = cavityH, so LOWERING
    // lockGrooveZ (or t) buys the same millimetre in BOTH — the only lever that pays twice, where cavityH
    // moves Rf alone. [00_07 HW.33 MATE-Ø, ⚖️ 2026-09-11]
    public static float BayonetZMismatchMm(AnchorAssemblyCem cem)
        => MathF.Abs(RadomeLiftZMm(cem) - FlangeTopZMm(cem));

    // The lug Z the mate REQUIRES: the rim lands on the sealing face and the socket sits lockGrooveZ above
    // that rim ⇒ the lug sits there too — 20.5 at the frozen dims, exactly lockGrooveZ over the face.
    // ⚖️ The raised collar that carries such a lug is RATIFIED (02_02 §4.4, 2026-09-11) and this is its Z.
    // It is NOT modelled: nothing sets its wall (no bayonet load model, 00_07 HW.33), and it rides AFTER the
    // rim boss — now applied (Radome.cs) — whose socket band it must share. The board layout HW.9 takes the
    // boss's rim-cavity ceiling as an input, not as a gate on this (⚖️ 2026-09-14).
    public static float RequiredLugZMm(AnchorAssemblyCem cem)
        => FlangeTopZMm(cem) + cem.Radome.LockGrooveZMm;

    // ── The seal mate under branch (а): the flange groove must sit INSIDE the radome's seal land with land on
    //    BOTH sides, and the ring must fit its gland. STRICT on purpose — a groove ending exactly at the land's
    //    edge, or a ring exactly filling the gland, is the zero-margin state nobody intends (the F3 lesson,
    //    00_07 HW.34). The margins are one slot clearance each at the frozen dims: the radome may sit one
    //    socket clearance off-centre and the ring is still backed all round. ──
    public static float SealLandMarginInnerMm(AnchorAssemblyCem cem)
        => CathodeFlange.ORingGrooveInnerRMm(cem.Flange) - Radome.SealLandInnerRMm(cem.Radome);
    public static float SealLandMarginOuterMm(AnchorAssemblyCem cem)
        => Radome.SealLandOuterRMm(cem.Radome) - CathodeFlange.ORingGrooveOuterRMm(cem.Flange);
    public static bool SealLandBacksTheGroove(AnchorAssemblyCem cem)
        => SealLandMarginInnerMm(cem) > 0f && SealLandMarginOuterMm(cem) > 0f;

    // MATE-Ø radial gap: radome inner-cavity radius − flange rim radius. <0 ⇒ the Ø25 disc cannot enter
    // the Ø(25−2·wall) cavity (radial interference). CEM-analytic, independent of lift / strategy.
    public static float MateRadialGapMm(AnchorAssemblyCem cem)
        => ((cem.Radome.DomeDiameterMm / 2f) - cem.Radome.WallThicknessMm) - (cem.Flange.FlangeDiameterMm / 2f);

    // RF clearance at the bayonet datum: antenna plane (cavity top) over the Ti flange top face.
    // Radome cavity z∈[lift, lift+cavityH], Ti at flangeTop ⇒ antenna↔Ti = (lift+cavityH) − flangeTop.
    //
    // 🔑 SUBSTITUTE AND THE SHANK CANCELS, which decides which levers exist at all:
    //     Rf = (shank + t/2 − lockGrooveZ) + cavityH − (shank + t) = cavityH − lockGrooveZ − t/2
    // So shank length is NOT a lever here, and only three things move this number: cavity height,
    // lock-groove Z, and flange thickness. ⛔ And the sign of the middle one is the opposite of the
    // intuitive reading: RAISING `lock_groove_z_mm` LOWERS the antenna (it shortens the lift), so
    // "lift the radome by raising the lock groove" runs backwards. Reaching OUR 12 mm working floor
    // (02_01 §5.3 asks ≥ 8; which number is acceptance, a mock-up settles — ⚖️ 2026-09-17) from today's 8.0 would need
    // +4 on `cavityH` (13 → 17); on the groove alone −0.5, i.e. a groove above the rim. Cavity height is
    // the one term here that does NOT move the rim — an algebraic fact about this function, ⛔ not a
    // recommendation: «raise the cavity to 15–17» is a REMOVED branch, because the ratified flat crown moves
    // the headroom the other way and the RF floor is set from BELOW by the board stack (00_07 HW.9).
    // [00_07 HW.33 MATE-Ø, ⚖️ 2026-09-11]
    public static float RfClearanceMm(AnchorAssemblyCem cem)
        => (RadomeLiftZMm(cem) + cem.Radome.CavityHeightMm) - FlangeTopZMm(cem);

    // ── Render: bring both parts into the flange frame for STL + interference measurement ──
    public static AssemblyVoxels Build(AnchorAssemblyCem cem)
    {
        // inboard candidate (MATE-Ø): clamp the lug protrusion so the tips stay within Ø25 (flush lugs).
        // Loses radial bayonet grip — the trade-off the metrics expose; ratified 2026-09-10 (00_07 HW.33).
        CathodeFlangeCem flangeCem = cem.MateStrategy == "inboard"
            ? cem.Flange with { LugProtrusionMm = 0f }
            : cem.Flange;
        Voxels voxFlange = CathodeFlange.Build(flangeCem);

        // Lift the radome (whole) onto the bayonet datum — vertex-translate, so Radome.Build stays untouched.
        // ⚠ At the frozen dims this seats the rim 5.0 mm BELOW the flange top face (the bayonet-Z deficit the
        // collar leg owns), so the applied rim boss now stands INSIDE the disc's envelope and the rendered
        // interference below grows with it — an audit finding about the un-reconciled Z, not about the boss.
        float fLift = RadomeLiftZMm(cem);
        Voxels voxRadome = MeshUtility.voxApplyTransformation(
            Radome.Build(cem.Radome), v => v + new Vector3(0f, 0f, fLift));

        if (cem.MateStrategy == "skirt")
            ApplyEnclosingSkirt(voxRadome, cem, fLift);

        Voxels voxMerged = new(voxFlange);
        voxMerged.BoolAdd(voxRadome);
        return new AssemblyVoxels(voxMerged, voxFlange, voxRadome);
    }

    // skirt candidate (MATE-Ø): open the radome's lower cavity to admit the Ø25 disc, wrap it with a
    // structural ring out to Ø(lug-tip + clearance), and cut a proper L-slot bayonet socket in that ring —
    // a circumferential lock groove at the lug Z (where the lugs sit after the quarter-turn) + axial entry
    // slots (where the lugs pass down from the rim). Only the INNER band [bore, lug-tip+clearance] is cut,
    // so the outer rim stays a structural wall (→ lug∩ring interference ≈ 0, the lug rides the groove). The
    // dome body stays Ø25 above (RF). Resolves MATE-Ø RADIALLY only. ⛔ WITHDRAWN 2026-09-10 (00_07 HW.33): it
    // deletes the flange face the ratified O-ring seals against — kept as the audit of the rejected branch.
    private static void ApplyEnclosingSkirt(Voxels voxRadome, AnchorAssemblyCem cem, float fLift)
    {
        float fSkirtTopZ = FlangeTopZMm(cem) + 1f;                       // cover the lugs (15.5) + disc top (17)
        float fBoreR = (cem.Flange.FlangeDiameterMm / 2f) + 0.3f;        // admit the Ø25 disc
        float fOuterR = LugTipRadiusMm(cem) + cem.SkirtClearanceMm;      // enclose the Ø29 lug tips
        float fH = fSkirtTopZ - fLift;
        LocalFrame oF = new(new Vector3(0f, 0f, fLift));

        voxRadome.BoolSubtract(new BaseCylinder(oF, fH, fBoreR).voxConstruct());   // open the cavity for the disc
        Voxels voxRing = new BaseCylinder(oF, fH, fOuterR).voxConstruct();
        voxRing.BoolSubtract(new BaseCylinder(oF, fH, fBoreR).voxConstruct());     // → structural ring [bore, outer]

        // L-slot bayonet socket cut into the ring (same primitive as Radome.Build's own socket).
        float fLugZ = FlangeLugZMm(cem);                                            // lugs sit here (15.5)
        float fSlot = cem.Radome.LugRadiusMm + cem.Radome.SlotClearanceMm;          // half-height / slot radius
        float fGrooveOuterR = LugTipRadiusMm(cem) + cem.Radome.SlotClearanceMm;     // cut only up to lug-tip + clearance
        LocalFrame oGrooveF = new(new Vector3(0f, 0f, fLugZ - fSlot));
        Voxels voxGroove = new BaseCylinder(oGrooveF, 2f * fSlot, fGrooveOuterR).voxConstruct();
        voxGroove.BoolSubtract(new BaseCylinder(oGrooveF, 2f * fSlot, fBoreR).voxConstruct());
        voxRing.BoolSubtract(voxGroove);                                            // circumferential lock groove

        for (int i = 0; i < cem.Flange.BayonetLugs; i++)                            // axial entry slots (lugs pass down)
        {
            float fAngle = 2f * MathF.PI * i / cem.Flange.BayonetLugs;
            Vector3 vecRadial = new(MathF.Cos(fAngle), MathF.Sin(fAngle), 0f);
            LocalFrame oSlot = new((vecRadial * fBoreR) + new Vector3(0f, 0f, fLift));
            voxRing.BoolSubtract(new BaseCylinder(oSlot, fLugZ - fLift, fSlot).voxConstruct());
        }

        voxRadome.BoolAdd(voxRing);
    }
}

// The assembled voxels + the two transformed parts (kept apart for the interference measurement).
internal sealed record AssemblyVoxels(Voxels Merged, Voxels Flange, Voxels Radome);
