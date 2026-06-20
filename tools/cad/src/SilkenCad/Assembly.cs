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

    // Bayonet-Z mismatch: at the bayonet datum the radome rim lands at `lift`; the O-ring squeeze wants it
    // at flangeTop + ORingGap. Their gap = the un-reconciled Z-stack error (Деталь3/Деталь4, HW.8/HW.17).
    public static float BayonetZMismatchMm(AnchorAssemblyCem cem)
        => MathF.Abs(RadomeLiftZMm(cem) - (FlangeTopZMm(cem) + cem.ORingGapMm));

    // MATE-Ø radial gap: radome inner-cavity radius − flange rim radius. <0 ⇒ the Ø25 disc cannot enter
    // the Ø(25−2·wall) cavity (radial interference). CEM-analytic, independent of lift / strategy.
    public static float MateRadialGapMm(AnchorAssemblyCem cem)
        => ((cem.Radome.DomeDiameterMm / 2f) - cem.Radome.WallThicknessMm) - (cem.Flange.FlangeDiameterMm / 2f);

    // RF clearance at the bayonet datum: antenna plane (cavity top) over the Ti flange top face.
    // Radome cavity z∈[lift, lift+cavityH], Ti at flangeTop ⇒ antenna↔Ti = (lift+cavityH) − flangeTop.
    public static float RfClearanceMm(AnchorAssemblyCem cem)
        => (RadomeLiftZMm(cem) + cem.Radome.CavityHeightMm) - FlangeTopZMm(cem);

    // ── Render: bring both parts into the flange frame for STL + interference measurement ──
    public static AssemblyVoxels Build(AnchorAssemblyCem cem)
    {
        // inboard candidate (MATE-Ø): clamp the lug protrusion so the tips stay within Ø25 (flush lugs).
        // Loses radial bayonet grip — a trade-off the metrics expose, a founder/bench call (HW.17).
        CathodeFlangeCem flangeCem = cem.MateStrategy == "inboard"
            ? cem.Flange with { LugProtrusionMm = 0f }
            : cem.Flange;
        Voxels voxFlange = CathodeFlange.Build(flangeCem);

        // Lift the radome (whole) onto the bayonet datum — vertex-translate, so Radome.Build stays untouched.
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
    // dome body stays Ø25 above (RF). Resolves MATE-Ø RADIALLY only — bayonet-Z / RF is a separate Z-reconcile.
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
