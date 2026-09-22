// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// PEEK Radome (Деталь 4, 02_01 §5.2 + 01_04 §5.5) — the radio-transparent dome that bayonets onto the
// Zone-3 cathode flange (Деталь 3) and caps the PCB. A HOLLOW PEEK shell — gotcha #9 is INVERTED here:
// the hollow is INTENTIONAL (outer voxConstruct − inner cavity), so the verify gate checks the WALL is
// present, not solidity. Cylinder body + a rounded shield bell on top (anti-overgrowth, no callus-grip
// edge, 01_04 §5.5) + a LOCAL INTERNAL RIM BOSS (step 3) that carries, radially one after the other, the
// bayonet socket in its OUTER band and the O-ring seal land in its INNER band + the bayonet socket itself
// (circumferential lock groove + axial entry slots mating the Деталь-3 lugs), cut in the outer band ONLY.
// The rim face (z = 0) is FLAT: the single O-ring groove is the FLANGE's (CathodeFlange.cs) and the seal land
// here closes it. The cathode breathes O₂ from the SIDE/perimeter (02_02 §1.2) — the dome does NOT seal it.
//
// ⚖️ What is APPLIED here (00_07 HW.33) and what is deliberately not:
//  • rim boss + flat rim + socket-in-the-outer-band — APPLIED 2026-09-14 (ratified 2026-09-10; ⚖️ 2026-09-14
//    «вхід»: designed to the rim-cavity ceiling now, and the board layout HW.9 takes that ceiling as an INPUT);
//  • the raised COLLAR that carries the lugs at Assembly.RequiredLugZMm (ratified 2026-09-11, 02_02 §4.4) is NOT
//    modelled — nothing sets its wall (no bayonet load model; a placeholder would print on the flange sheet as a
//    decision), so the flange still carries its lugs at mid-disc and the capsule-end audit still reports the
//    bayonet-Z deficit. The socket keeps today's L-slot shape, clipped to the outer band, until that leg reshapes
//    it — socket and collar are the female and male halves of one band;
//  • the FLAT CROWN (R5, ratified 2026-09-11) is APPLIED since 2026-09-22 — its gate was ⚖️ HW.30, and that
//    verdict put the pad BESIDE the piezo (02_01 §6), which leaves the board stack under the 16.0 mm the
//    crown fixes. `BellRadiusMm` now DRIVES the edge round; `BellRiseMm` stays the canon floor verify
//    checks against. ⛔ `draw radome` is STILL refused, and for the OTHER reason: the socket is reshaped
//    by the collar leg, so the sheet waits on the LAST of the two changes, never on this one alone.
// ⚠ MATE-Ø: the flange lugs still protrude to ~Ø29 (asis); `inboard` clamps them — the collar leg owns the mate.
internal static class Radome
{
    // ── Rim-boss radial layout — CEM-derived, the same chain as 52_z_stack_tolerance.rim_boss_radial_budget ──
    // From the dome OD inward: [socket band][seal band] = the boss; what is left is the rim cavity.
    //   socket band = lug radius + slot clearance          (the entry slot must clear the lug)
    //   seal band   = gland width + 2·slot clearance       (the land backs the ring even at full socket misalignment)
    // 🔴 Every term is a MINIMUM, so the cavity is a CEILING with zero tolerance in it (00_07 HW.33): the Ø handed
    //    to HW.9 is an upper bound on the board, never a nominal to design a board against.
    // 🔗 C#↔Python crossing, EXPLICIT: script 52 derives the identical numbers from the same manifest fields and
    //    writes them to its cache (§rim_boss_radial_budget, §applied_gland); RadomeTests pins these against it.
    public static float SocketBandMm(RadomeCem cem) => cem.LugRadiusMm + cem.SlotClearanceMm;
    public static float SealBandMm(RadomeCem cem) => cem.ORing.WidthMm + (2f * cem.SlotClearanceMm);
    public static float BossRadialMm(RadomeCem cem) => SocketBandMm(cem) + SealBandMm(cem);
    public static float RimCavityDiameterMm(RadomeCem cem) => cem.DomeDiameterMm - (2f * BossRadialMm(cem));

    // The seal land = the boss's inner band, as radii [inner, outer]. Its outer edge is where the socket begins.
    public static float SealLandInnerRMm(RadomeCem cem) => (cem.DomeDiameterMm / 2f) - BossRadialMm(cem);
    public static float SealLandOuterRMm(RadomeCem cem) => (cem.DomeDiameterMm / 2f) - SocketBandMm(cem);

    // Boss height = the socket's top (lock-groove Z + slot radius): the boss exists to carry the socket and the
    // land, and the verdict names no height of its own — DERIVED, not a field, so no number is invented.
    public static float BossHeightMm(RadomeCem cem) => cem.LockGrooveZMm + SocketBandMm(cem);

    // The socket pocket's radial extent [inner, outer]: today's L-slot cuts (lock groove + entry slots, both of
    // radius `socket band` about the wall's inner face) CLIPPED to the outer band, so no cut reaches the seal land.
    // The outer edge stays where the shipped socket always had it — `inner wall + slot radius`, leaving
    // `wall − slot radius` of skin — so the pocket is `socket band − skin` deep, not the full band: script 52's
    // budget counts no skin (every term a minimum) and a pocket cut to the dome OD would breach the shell. The
    // collar leg (00_07 HW.33) sizes the lug protrusion against THIS depth, not against the band.
    public static float SocketPocketInnerRMm(RadomeCem cem) => SealLandOuterRMm(cem);
    // Skin first, pocket from it: `wall − slot radius` is the definition, and computing the pocket edge as
    // `inner wall + slot radius` then subtracting it from the OD accumulates two float32 roundings that read
    // the 0.2 mm skin as 1.99998 voxels on the radome's own 0.1 mm grid — a threshold miss with no geometry in it.
    public static float SocketSkinMm(RadomeCem cem) => cem.WallThicknessMm - SocketBandMm(cem);
    public static float SocketPocketOuterRMm(RadomeCem cem) => (cem.DomeDiameterMm / 2f) - SocketSkinMm(cem);

    public static Voxels Build(RadomeCem cem)
    {
        float fR = cem.DomeDiameterMm / 2f;
        float fWall = cem.WallThicknessMm;
        float fCavH = cem.CavityHeightMm;
        float fInnerR = fR - fWall;

        // 1. Outer dome — cylinder body + FLAT CROWN with an R-round edge (⚖️ 2026-09-11, 01_04 §5.5;
        //    applied 2026-09-22 once ⚖️ HW.30 placed the pad BESIDE the piezo, 02_01 §6). The crown is a
        //    quarter-round from the body OD up to a flat top: a torus of minor radius `BellRadiusMm` whose
        //    major circle sits at r = fR − Rb in the plane z = fCavH, plus the flat core cylinder inside it.
        //    🔑 The rise is NOT a second number — by construction it EQUALS the edge round, so `BellRadiusMm`
        //    is the one DRIVER and `BellRiseMm` stays what it always was: the canon FLOOR that verify checks
        //    the measured rise against (≥3, 01_04 §5.5 — measured 5.0 here, 2.2 mm of margin).
        //    ⛔ The hemisphere it replaces was NOT a canon requirement: §5.5 asks for a rounded top EDGE, and
        //    the sphere gave rise 12.5 = fR, i.e. an excess the verdict removed (canon: rise 12.5 → 5.0,
        //    height over bark 25.5 → 18.0, internal height 23.5 → 16.0 = cavity 13.0 + inner round 3.0).
        //    The torus reaches BELOW z = fCavH (down to fCavH − Rb, radially [fR−2Rb, fR]) and that half lies
        //    inside the body cylinder — an overlap, never a touching seam (step 3 records what a seam costs).
        float fRb = cem.BellRadiusMm;
        float fCrownCoreR = fR - fRb;
        LocalFrame oCrown = new(new Vector3(0f, 0f, fCavH));
        Voxels voxDome = new BaseCylinder(new LocalFrame(Vector3.Zero), fCavH, fR).voxConstruct();
        voxDome.BoolAdd(new BaseRing(oCrown, fCrownCoreR, fRb).voxConstruct());
        voxDome.BoolAdd(new BaseCylinder(oCrown, fRb, fCrownCoreR).voxConstruct());

        // 2. Hollow it — subtract the inner cavity, open at the rim (z=0). Wall = fWall everywhere, INCLUDING
        //    under the crown: offsetting the crown surface inward by the wall keeps the round's CENTRE circle
        //    where it is and shrinks its radius to Rb − wall, so the inner flat top lands at fCavH + (Rb − wall)
        //    and the inner round meets the bore exactly at fInnerR = fR − wall (no step, no seam).
        //    ⚠ A uniform wall under the crown is the READING of «стінка купола лишається 2.0» (02_02 §3.5) —
        //    the verdict names the wall over the antenna, and script 52 takes the same reading (§crown).
        //    🔑 Built as ONE body and subtracted ONCE: its three parts overlap substantially, so the cavity
        //    carries no sub-voxel seam into the wall it defines.
        float fRbIn = fRb - fWall;
        Voxels voxCavity = new BaseCylinder(new LocalFrame(Vector3.Zero), fCavH, fInnerR).voxConstruct();
        voxCavity.BoolAdd(new BaseRing(oCrown, fCrownCoreR, fRbIn).voxConstruct());
        voxCavity.BoolAdd(new BaseCylinder(oCrown, fRbIn, fCrownCoreR).voxConstruct());
        voxDome.BoolSubtract(voxCavity);

        // 3. Rim BOSS — a local internal annulus from the seal-land inner R out to the socket pocket's outer R,
        //    from the rim up to the socket's top. It thickens the RIM only (the dome wall over the antenna stays
        //    fWall — RF untouched) and is what gives the seal land a width the socket does not share: the shipped
        //    socket used to leave 0.2 of 2.0 mm of land under its entry slots on 16 % of the circle (00_07 HW.33).
        //    ⚠ The annulus deliberately OVERLAPS the wall (its outer R lies inside the wall's solid; the socket cut
        //    below carves the pocket out of it again): an annulus ending exactly at the inner wall radius met the
        //    wall SURFACE-to-surface, and the union of two touching voxel bodies keeps a seam of sub-voxel voids —
        //    measured 2026-09-14 as ~6 % missing solid in a two-voxel strip across r = 10.5 on a part with nothing
        //    cut there. Overlap costs nothing and leaves the seal land's edge measurable (Validation.MeasureRadome).
        LocalFrame oRim = new(Vector3.Zero);
        float fBossH = BossHeightMm(cem);
        Voxels voxBoss = new BaseCylinder(oRim, fBossH, SocketPocketOuterRMm(cem)).voxConstruct();
        voxBoss.BoolSubtract(new BaseCylinder(oRim, fBossH, SealLandInnerRMm(cem)).voxConstruct());
        voxDome.BoolAdd(voxBoss);

        // 4. Bayonet socket — a circumferential lock groove (lugs rotate into) + axial entry slots (lugs pass
        //    from the rim): the same L-slot primitives as before, then CLIPPED to the outer band so no cut enters
        //    the seal land. Radial extent = [SocketPocketInnerRMm, SocketPocketOuterRMm].
        float fSlotR = SocketBandMm(cem);
        LocalFrame oGrooveF = new(new Vector3(0f, 0f, cem.LockGrooveZMm - fSlotR));
        Voxels voxSocket = new BaseCylinder(oGrooveF, 2f * fSlotR, fInnerR + fSlotR).voxConstruct();
        voxSocket.BoolSubtract(new BaseCylinder(oGrooveF, 2f * fSlotR, fInnerR).voxConstruct());
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            float fAngle = 2f * MathF.PI * i / cem.BayonetLugs;
            Vector3 vecRadial = new(MathF.Cos(fAngle), MathF.Sin(fAngle), 0f);
            LocalFrame oSlot = new(vecRadial * fInnerR);   // base at the inner wall, axis +Z (default)
            voxSocket.BoolAdd(new BaseCylinder(oSlot, cem.LockGrooveZMm, fSlotR).voxConstruct());
        }
        Voxels voxOuterBand = new BaseCylinder(oRim, fCavH, fR).voxConstruct();
        voxOuterBand.BoolSubtract(new BaseCylinder(oRim, fCavH, SocketPocketInnerRMm(cem)).voxConstruct());
        voxSocket.BoolIntersect(voxOuterBand);
        voxDome.BoolSubtract(voxSocket);

        // The rim face (z = 0) is left FLAT on purpose: ⚖️ 2026-09-10 put the ONE O-ring groove in the flange
        // (CathodeFlange.cs) and this land closes it. The counter-groove that used to be cut here made a
        // 0.9 + 0.9 pair under a 1.78 cord (a −1.1 % squeeze that did not seal); it is gone, not shallower.
        return voxDome;
    }
}
