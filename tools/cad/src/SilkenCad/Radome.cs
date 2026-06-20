using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// PEEK Radome (Деталь 4, 02_01 §5.2 + 01_04 §5.5) — the radio-transparent dome that bayonets onto the
// Zone-3 cathode flange (Деталь 3) and caps the PCB. A HOLLOW PEEK shell — gotcha #9 is INVERTED here:
// the hollow is INTENTIONAL (outer voxConstruct − inner cavity), so the verify gate checks the WALL is
// present, not solidity. Cylinder body + a rounded shield bell on top (anti-overgrowth, no callus-grip
// edge, 01_04 §5.5) + a bayonet socket (circumferential lock groove + axial entry slots mating the
// Деталь-3 lugs) + a rim O-ring groove. The cathode breathes O₂ from the SIDE/perimeter (02_02 §1.2) —
// the dome does NOT seal it.
//
// ⚠ MATE-Ø FLAG (HW.17): Деталь-3 lugs protrude radially to ~Ø29 (flange Ø25 + 2·2); a cap that slides
// over them needs OD > Ø25, conflicting with the frozen "radome Ø25" (02_02 §1.3). This generator keeps
// the dome body Ø25 and models the socket at the lug Ø for mate-fit; the enclosing-skirt Ø (or moving the
// lugs inboard to keep Ø25) is a founder/bench reconciliation — SURFACED, not fudged.
internal static class Radome
{
    public static Voxels Build(RadomeCem cem)
    {
        float fR = cem.DomeDiameterMm / 2f;
        float fWall = cem.WallThicknessMm;
        float fCavH = cem.CavityHeightMm;
        float fInnerR = fR - fWall;

        // 1. Outer dome — cylinder body + hemispherical cap (rounded shield bell): smooth, no callus-grip
        //    edge. Cap rise = fR ≥ BellRiseMm, cap edge radius = fR ≥ BellRadiusMm (both gated in verify).
        Voxels voxDome = new BaseCylinder(new LocalFrame(Vector3.Zero), fCavH, fR).voxConstruct();
        voxDome.BoolAdd(new BaseSphere(new LocalFrame(new Vector3(0f, 0f, fCavH)), fR).voxConstruct());

        // 2. Hollow it — subtract the inner cavity (cylinder + inner cap), open at the rim (z=0). Wall = fWall.
        voxDome.BoolSubtract(new BaseCylinder(new LocalFrame(Vector3.Zero), fCavH, fInnerR).voxConstruct());
        voxDome.BoolSubtract(new BaseSphere(new LocalFrame(new Vector3(0f, 0f, fCavH)), fInnerR).voxConstruct());

        // 3. Bayonet socket — a circumferential lock groove (lugs rotate into) + axial entry slots (lugs
        //    pass from the rim). Pocket radius = lug + clearance (mate-fit; see MATE-Ø flag).
        float fSlotR = cem.LugRadiusMm + cem.SlotClearanceMm;
        LocalFrame oGrooveF = new(new Vector3(0f, 0f, cem.LockGrooveZMm - fSlotR));
        Voxels voxGroove = new BaseCylinder(oGrooveF, 2f * fSlotR, fInnerR + fSlotR).voxConstruct();
        voxGroove.BoolSubtract(new BaseCylinder(oGrooveF, 2f * fSlotR, fInnerR).voxConstruct());
        voxDome.BoolSubtract(voxGroove);
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            float fAngle = 2f * MathF.PI * i / cem.BayonetLugs;
            Vector3 vecRadial = new(MathF.Cos(fAngle), MathF.Sin(fAngle), 0f);
            LocalFrame oSlot = new(vecRadial * fInnerR);   // base at the inner wall, axis +Z (default)
            voxDome.BoolSubtract(new BaseCylinder(oSlot, cem.LockGrooveZMm, fSlotR).voxConstruct());
        }

        // 4. O-ring groove on the rim wall (z=0 face, mate the Деталь-3 O-ring) — annular into the wall.
        LocalFrame oRim = new(Vector3.Zero);
        Voxels voxORing = new BaseCylinder(oRim, cem.ORingGrooveDepthMm, fInnerR + cem.ORingGrooveWidthMm).voxConstruct();
        voxORing.BoolSubtract(new BaseCylinder(oRim, cem.ORingGrooveDepthMm, fInnerR).voxConstruct());
        voxDome.BoolSubtract(voxORing);

        return voxDome;
    }
}
