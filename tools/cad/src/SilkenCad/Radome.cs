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
//    modelled — strength does not size its wall (model 73, 02_02 §4.4: there is still no bayonet load model, but
//    the force no longer sizes the wall — the process floor does), a placeholder would print on the flange sheet as a
//    decision, and its running clearance moves the root (00_07 HW.9, under the crown pause), so the flange still carries its lugs at mid-disc and the capsule-end audit still reports the
//    bayonet-Z deficit. The socket keeps today's L-slot shape, clipped to the outer band, until that leg reshapes
//    it — socket and collar are the female and male halves of one band;
//  • the FLAT CROWN (R5, ratified 2026-09-11) is APPLIED since 2026-09-22 — its gate was ⚖️ HW.30, and that
//    verdict put the pad BESIDE the piezo (02_01 §6; the piezo and its pad were then cut on 2026-09-29,
//    HW.30 — the flat crown stays as ratified), which leaves the board stack under the 16.0 mm the
//    crown fixes. `BellRadiusMm` now DRIVES the edge round; `BellRiseMm` stays the canon floor verify
//    checks against. ⛔ `draw radome` is STILL refused, on TWO other grounds: the socket is reshaped
//    by the collar leg, and the BME280 pocket floor is a PLACEHOLDER (HW.29) — the sheet waits on the LAST of those
//    changes, never on this one alone.
//  • the DOME Ø is no longer frozen: the ROOT verdict (⚖️ founder 2026-09-29, 00_07 HW.9 → HW.33) opened Ø25 for the board
//    contour, and the Ø is DERIVED (RadomeCem.DomeDiameterMm) — applied 2026-09-30 with the vent facet + BME280 pocket
//    (⚖️ 2026-09-29, 02_01 §3.4; steps 5–7 below). The gland fill stayed at 80 % (⚖️ delegated 2026-09-30, 02_02 §3.2).
// ⚠ MATE-Ø: the flange lugs still protrude past the dome (asis); `inboard` clamps them — the collar leg owns the mate.
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


    // ── Vent facet + BME280 pocket (⚖️ founder 2026-09-29, 02_01 §3.4 — applied 2026-09-30 together with the root-opened
    //    dome, 00_07 HW.32 ⊂ HW.33). Gore VE7 is glued INSIDE on a FLAT facet of the vertical wall; the sensor sits in a
    //    POCKET sealed to that vent, so the capsule stays sealed and the desiccant (02_02 §3.4) stays dry. ──
    // The facet is an inward PAD: material ADDED between a chord plane and the cylindrical inner wall, so the wall over the
    // antenna is never thinned. Its plane sits `VentFacetChordRMm` from the axis; the pad is one sagitta thick at its centre.
    public static float InnerRMm(RadomeCem cem) => (cem.DomeDiameterMm / 2f) - cem.WallThicknessMm;
    public static float VentRingOdMm(RadomeCem cem) => cem.VentRingIdMm + (2f * cem.VentRingWallMm);
    public static float VentFacetChordRMm(RadomeCem cem)
    {
        float fRin = InnerRMm(cem), fHalf = cem.VentFacetWidthMm / 2f;
        return MathF.Sqrt((fRin * fRin) - (fHalf * fHalf));
    }
    public static float VentPadThicknessMm(RadomeCem cem) => InnerRMm(cem) - VentFacetChordRMm(cem);
    // The vertical band a ring of half-width h may occupy on the facet: from the boss top up to where the crown's inner
    // round (centre circle r = R − Rb, minor radius Rb − wall) passes the facet plane at that half-width — above that the
    // flat narrows to a D and a full-width seat no longer exists. This is what decides VE70205 vs VE70308 (⚖️ conditional).
    public static float VentBandBottomZMm(RadomeCem cem) => BossHeightMm(cem);
    public static float VentBandTopZMm(RadomeCem cem, float fHalfWidthMm)
    {
        float fChord = VentFacetChordRMm(cem);
        float fEdgeR = MathF.Sqrt((fChord * fChord) + (fHalfWidthMm * fHalfWidthMm));
        float fCore = (cem.DomeDiameterMm / 2f) - cem.BellRadiusMm;
        float fRho = cem.BellRadiusMm - cem.WallThicknessMm;
        float fD = fEdgeR - fCore;
        if (fD <= 0f) return cem.CavityHeightMm + fRho;
        if (fD >= fRho) return cem.CavityHeightMm;
        return cem.CavityHeightMm + MathF.Sqrt((fRho * fRho) - (fD * fD));
    }
    public static float VentBandMm(RadomeCem cem, float fRingOdMm) => VentBandTopZMm(cem, fRingOdMm / 2f) - VentBandBottomZMm(cem);
    public static bool VentRingFits(RadomeCem cem, float fRingIdMm)
    {
        float fOd = fRingIdMm + (2f * cem.VentRingWallMm);
        return fOd < VentBandMm(cem, fOd) && fOd < cem.VentFacetWidthMm;
    }
    public static bool VentRingFits(RadomeCem cem) => VentRingFits(cem, cem.VentRingIdMm);
    public const float VentRingIdVe70308Mm = 9.1f;   // the other Gore size the verdict names — reported, never built
    public static float VentZMm(RadomeCem cem) => (VentBandBottomZMm(cem) + VentBandTopZMm(cem, VentRingOdMm(cem) / 2f)) / 2f;
    public static float VentHoleAreaMm2(RadomeCem cem) => cem.VentHoles * MathF.PI / 4f * cem.VentHoleDiameterMm * cem.VentHoleDiameterMm;
    public static float VentActiveDiameterMm(RadomeCem cem) => 2f * MathF.Sqrt(cem.VentActiveAreaMm2 / MathF.PI);
    public static float VentPathLengthMm(RadomeCem cem) => cem.WallThicknessMm + VentPadThicknessMm(cem);   // wall the air crosses at the hole
    public static Vector3 VentDir(RadomeCem cem)
    {
        float fA = cem.VentAzimuthDeg * MathF.PI / 180f;
        return new Vector3(MathF.Cos(fA), MathF.Sin(fA), 0f);
    }
    public static Vector3 VentTangent(RadomeCem cem) { Vector3 d = VentDir(cem); return new Vector3(-d.Y, d.X, 0f); }

    // Pocket housing — two boxes and a passage. DUCT: stands on the boss top OUTSIDE the rim cavity (one running clearance past
    // anything the rim cavity admits, so it is never in the board's way); its cavity faces the vent seat. CHAMBER: over the
    // RF-deck edge INSIDE the board radius, open at the bottom onto the board — that rim is the gasket land the area budget
    // counts (board_area_budget.rb). BRIDGE: the passage between them, hung one clearance above the board edge.
    // ⛔ The pocket floor is a PLACEHOLDER (the RF-deck top; HW.29 B2B/rigid-flex and HW.9 own it) — nothing here prints on a sheet.
    public const float BridgeBoardClearanceMm = 0.3f;   // the bridge floor hangs this far above the board top — same order as the socket running clearance
    public const float PocketVolumeCeilingMm3 = 300f;   // «кишеня 0.3 см³ — секунди»: the volume the verdict's response-time ground was argued at (02_01 §3.4)
    public const float VapourDiffusivityM2S = 2.5e-5f;  // water vapour in air, the shortlist's book value (radome_vent_shortlist §2.2)
    public static float DuctInnerRMm(RadomeCem cem) => (RimCavityDiameterMm(cem) / 2f) + cem.SlotClearanceMm;
    public static float DuctCavityInnerRMm(RadomeCem cem) => DuctInnerRMm(cem) + cem.PocketWallMm;
    public static float DuctCavityDepthMm(RadomeCem cem) => VentFacetChordRMm(cem) - DuctCavityInnerRMm(cem);   // air in front of the vent seat, facet centre
    public static float PocketTopZMm(RadomeCem cem) => cem.PocketFloorOverRimMm + cem.PocketHeightMm;                 // the cavity ceiling all three share
    public static float PocketHousingTopZMm(RadomeCem cem) => PocketTopZMm(cem) + cem.PocketWallMm;
    public static float ChamberCavityOuterRMm(RadomeCem cem) => cem.PocketOuterRadiusMm - cem.PocketWallMm;
    public static float ChamberCavityInnerRMm(RadomeCem cem) => ChamberCavityOuterRMm(cem) - cem.PocketOpeningDepthMm;
    public static float ChamberOuterWidthMm(RadomeCem cem) => cem.PocketOpeningWidthMm + (2f * cem.PocketWallMm);
    public static float BridgeFloorZMm(RadomeCem cem) => cem.PocketFloorOverRimMm + BridgeBoardClearanceMm;
    public static float BridgePassageZMm(RadomeCem cem) => BridgeFloorZMm(cem) + cem.PocketWallMm;
    public static float BridgePassageHeightMm(RadomeCem cem) => PocketTopZMm(cem) - BridgePassageZMm(cem);
    public static float InnerTopZMm(RadomeCem cem) => cem.CavityHeightMm + cem.BellRadiusMm - cem.WallThicknessMm;   // flat inner top under the crown
    // Analytic pocket air volume — the three cavity boxes; the passage is counted between the two cavity faces it joins.
    public static float PocketVolumeMm3(RadomeCem cem)
    {
        float fDuct = cem.VentFacetWidthMm * DuctCavityDepthMm(cem) * (PocketTopZMm(cem) - VentBandBottomZMm(cem));
        float fChamber = cem.PocketOpeningWidthMm * cem.PocketOpeningDepthMm * cem.PocketHeightMm;
        float fBridge = cem.PocketOpeningWidthMm * (DuctCavityInnerRMm(cem) - ChamberCavityOuterRMm(cem)) * BridgePassageHeightMm(cem);
        return fDuct + fChamber + fBridge;
    }
    // Diffusive settling time of the pocket air behind the hole(s), τ ≈ V·L/(D·A) — the shortlist's own estimate, without the
    // membrane's resistance; an ORDER, not a prediction (Bosch's 1 s needs ≈ 1 m/s of flow). Seconds, from mm inputs.
    public static float VentTauEstimateS(RadomeCem cem)
        => PocketVolumeMm3(cem) * VentPathLengthMm(cem) / (VapourDiffusivityM2S * VentHoleAreaMm2(cem)) * 1e-6f;

    // A box from its radial span [rIn, rOut] (along the vent meridian), tangential width and z span — base at the bottom centre.
    private static Voxels RadialBox(RadomeCem cem, float fRIn, float fROut, float fWidth, float fZ0, float fZ1)
    {
        Vector3 vecPos = (VentDir(cem) * ((fRIn + fROut) / 2f)) + new Vector3(0f, 0f, fZ0);
        LocalFrame oF = new(vecPos, Vector3.UnitZ, VentTangent(cem));   // local X = tangential (width), local Y = radial (depth)
        return new BaseBox(oF, fZ1 - fZ0, fWidth, fROut - fRIn).voxConstruct();
    }

    public static Voxels Build(RadomeCem cem)
    {
        float fR = cem.DomeDiameterMm / 2f;
        float fWall = cem.WallThicknessMm;
        float fCavH = cem.CavityHeightMm;
        float fInnerR = fR - fWall;

        // 1. Outer dome — cylinder body + FLAT CROWN with an R-round edge (⚖️ 2026-09-11, 01_04 §5.5;
        //    applied 2026-09-22 once ⚖️ HW.30 placed the pad BESIDE the piezo, 02_01 §6; piezo and pad cut 2026-09-29, crown stays). The crown is a
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

        // 5. Vent FACET — an inward pad between the chord plane and the wall over the facet width, from just inside the boss
        //    top (an overlap into solid, never a seam) up to the flat inner top. Radially it reaches only into the socket
        //    SKIN (wall − slot radius = 0.2): the socket pocket beyond it is a cut this pad must never refill.
        float fSkinOverlap = MathF.Min(0.2f, SocketSkinMm(cem));
        float fBoss0 = BossHeightMm(cem) - 0.3f;
        voxDome.BoolAdd(RadialBox(cem, VentFacetChordRMm(cem), fInnerR + fSkinOverlap, cem.VentFacetWidthMm, fBoss0, InnerTopZMm(cem)));

        // 6. Pocket HOUSING — duct (on the boss, outside the rim cavity) + chamber (over the board edge) + bridge (above the
        //    board edge), then their cavities. Solid first, cavities after: the three boxes overlap one another and the wall,
        //    so no touching-face seam survives (step 3 records what a seam costs).
        float fHousingTop = PocketHousingTopZMm(cem);
        voxDome.BoolAdd(RadialBox(cem, DuctInnerRMm(cem), fInnerR + fSkinOverlap, cem.VentFacetWidthMm + (2f * cem.PocketWallMm), fBoss0, fHousingTop));
        voxDome.BoolAdd(RadialBox(cem, ChamberCavityInnerRMm(cem) - cem.PocketWallMm, cem.PocketOuterRadiusMm, ChamberOuterWidthMm(cem), cem.PocketFloorOverRimMm, fHousingTop));
        voxDome.BoolAdd(RadialBox(cem, ChamberCavityOuterRMm(cem), DuctCavityInnerRMm(cem), ChamberOuterWidthMm(cem), BridgeFloorZMm(cem), fHousingTop));
        // duct cavity: its outer face IS the flat facet (the chord plane) — the seat the vent is glued to
        voxDome.BoolSubtract(RadialBox(cem, DuctCavityInnerRMm(cem), VentFacetChordRMm(cem), cem.VentFacetWidthMm, BossHeightMm(cem), PocketTopZMm(cem)));
        // chamber cavity: open at the bottom onto the board (cut past the floor), the sensor stands on the board inside it
        voxDome.BoolSubtract(RadialBox(cem, ChamberCavityInnerRMm(cem), ChamberCavityOuterRMm(cem), cem.PocketOpeningWidthMm, cem.PocketFloorOverRimMm - 0.5f, PocketTopZMm(cem)));
        // bridge passage: pokes one clearance into both cavities so the three volumes are ONE air space
        voxDome.BoolSubtract(RadialBox(cem, ChamberCavityOuterRMm(cem) - cem.SlotClearanceMm, DuctCavityInnerRMm(cem) + cem.SlotClearanceMm,
                                       cem.PocketOpeningWidthMm, BridgePassageZMm(cem), PocketTopZMm(cem)));

        // 7. Gore target RING on the facet (a raised locating lip, axis radial, standing INTO the duct cavity) + the through
        //    HOLE(s) from the seat to the outside. One hole today (VentHoles): spread on a pitch circle if ever more than one.
        Vector3 vecOut = VentDir(cem);
        Vector3 vecSeat = (vecOut * VentFacetChordRMm(cem)) + new Vector3(0f, 0f, VentZMm(cem));
        LocalFrame oRing = new(vecSeat, -vecOut);
        Voxels voxRing = new BaseCylinder(oRing, cem.VentRingHeightMm, VentRingOdMm(cem) / 2f).voxConstruct();
        voxRing.BoolSubtract(new BaseCylinder(oRing, cem.VentRingHeightMm, cem.VentRingIdMm / 2f).voxConstruct());
        voxDome.BoolAdd(voxRing);
        float fPitchR = cem.VentHoles > 1 ? (VentActiveDiameterMm(cem) - cem.VentHoleDiameterMm) / 2f : 0f;
        for (int i = 0; i < cem.VentHoles; i++)
        {
            float fAngle = 2f * MathF.PI * i / cem.VentHoles;
            Vector3 vecOffset = (VentTangent(cem) * (fPitchR * MathF.Cos(fAngle))) + new Vector3(0f, 0f, fPitchR * MathF.Sin(fAngle));
            LocalFrame oHole = new(vecSeat + vecOffset - (vecOut * 0.5f), vecOut);
            voxDome.BoolSubtract(new BaseCylinder(oHole, VentPathLengthMm(cem) + 1.0f, cem.VentHoleDiameterMm / 2f).voxConstruct());
        }

        // The rim face (z = 0) is left FLAT on purpose: ⚖️ 2026-09-10 put the ONE O-ring groove in the flange
        // (CathodeFlange.cs) and this land closes it. The counter-groove that used to be cut here made a
        // 0.9 + 0.9 pair under a 1.78 cord (a −1.1 % squeeze that did not seal); it is gone, not shallower.
        return voxDome;
    }
}
