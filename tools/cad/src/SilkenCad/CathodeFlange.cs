// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Zone 3 cathode flange (Деталь 3, 01_01 §1 + 02_02 §1.2) — the capsule-side anchor end. A SOLID Ti
// flange (Ø25 frozen) on the barbed Zone-3 shank that press-fits into the PEEK Zone-2 sleeve, with
// radial bayonet lugs that mate the PEEK Radome (Деталь 4, фаза 2). Reuses the §4.3 mechanical lock
// for the shank + barbs (no duplication); the lock cuts a DIN-471 groove only where `MechanicalLock.HasGroove`
// says one exists, and this end has none since ⚖️ 2026-09-18 (00_07 HW.26). Solid bodies come from ShapeKernel voxConstruct
// (gotcha #9 — never an SDF field left open at the bbox caps); the thin barb ridges ride the MechanicalLock split.
// Z: shank z∈[0,shankLen] (deep, into PEEK) → flange on top z∈[shankLen, shankLen+thickness] (capsule
// side). Pogo pads sit on the top face (Hard Gold = coating, not geometry); the cathode catalytic zone
// is the side/perimeter (Laccase/ZIF + PTFE-GDL, O₂ from the side under the radome bell — 02_02 §1.2).
// The top face also carries the ONE O-ring groove of the capsule seal (step 5) — the radome rim is flat and
// lands on this face as the hard datum (00_07 HW.33 branch (а), applied 2026-09-14).
internal static class CathodeFlange
{
    // Map the flange CEM's shank fields onto the §4.3 MechanicalLock CEM — reuse, не дублюй.
    // Internal (not private): Validation.MeasureFlange reuses the same shank SDF for the barb count.
    internal static MechanicalLockCem ShankCem(CathodeFlangeCem c) => new()
    {
        Name = c.Name,
        VoxelSizeMm = c.VoxelSizeMm,
        ShankDiameterMm = c.ShankDiameterMm,
        ShankLengthMm = c.ShankLengthMm,
        BoreDiameterMm = c.BoreDiameterMm,
        ContactStartMm = c.ContactStartMm,
        ContactLengthMm = c.ContactLengthMm,
        BarbRows = c.BarbRows,
        BarbHeightMm = c.BarbHeightMm,
        LeadAngleDeg = c.LeadAngleDeg,
        TrailAngleDeg = c.TrailAngleDeg,
        GrooveOffsetMm = c.GrooveOffsetMm,
        GrooveWidthMm = c.GrooveWidthMm,
        GrooveDepthMm = c.GrooveDepthMm,
    };

    // ── The ONE O-ring groove (⚖️ 2026-09-10, applied 2026-09-14, 00_07 HW.33 branch (а)) — DERIVED, not stored ──
    // Depth and width come from the gland spec (CathodeFlangeCem.ORing); the radial position comes from the
    // radome's rim-boss layout, mirrored through the fields the two parts share (Ø, lug radius, slot clearance):
    // the groove's outer edge sits one slot clearance inside the seal land's outer edge (flangeR − socket band),
    // so the land backs the ring on BOTH sides even at full socket misalignment. Same chain as Radome.SealLand*,
    // pinned by AssemblyTests.Seal_Land_Backs_The_Groove_With_One_Slot_Clearance_On_Each_Side.
    public static float ORingGrooveDepthMm(CathodeFlangeCem c) => c.ORing.DepthMm;
    public static float ORingGrooveWidthMm(CathodeFlangeCem c) => c.ORing.WidthMm;
    public static float ORingGrooveOuterRMm(CathodeFlangeCem c)
        => (c.FlangeDiameterMm / 2f) - (c.LugRadiusMm + c.SlotClearanceMm) - c.SlotClearanceMm;
    public static float ORingGrooveInnerRMm(CathodeFlangeCem c) => ORingGrooveOuterRMm(c) - ORingGrooveWidthMm(c);

    public static Voxels Build(CathodeFlangeCem cem)
    {
        float fShankLen = cem.ShankLengthMm;
        float fFlangeR = cem.FlangeDiameterMm / 2f;
        float fThick = cem.FlangeThicknessMm;

        // 1. Barbed Zone-3 shank (reuse §4.3 lock): solid Ø + barbs + bus channel, z∈[0,shankLen]; a groove only where
        //    HasGroove — none on this end since ⚖️ 2026-09-18 (00_07 HW.26: zero groove fields, manifest AND defaults).
        Voxels voxPart = MechanicalLock.Build(ShankCem(cem));

        // 2. Solid Ø25 flange disc on top — a true filled cylinder (gotcha #9: voxConstruct, NOT the SDF ctor).
        LocalFrame oFlange = new(new Vector3(0f, 0f, fShankLen));
        voxPart.BoolAdd(new BaseCylinder(oFlange, fThick, fFlangeR).voxConstruct());

        // 3. Bayonet lugs — radial pins evenly spaced around the flange rim (mate the Радом socket, фаза 2).
        //    Each pin's local-Z = the radial outward direction; it overlaps the rim by fOverlap to fuse.
        //    ⚖️ Their Z is the mid-disc `shank + t/2`; the ratified raised COLLAR (02_02 §4.4) that would carry
        //    them at Assembly.RequiredLugZMm is not modelled — its wall is set by nothing (00_07 HW.33).
        float fLugZ = fShankLen + (fThick / 2f);
        const float fOverlap = 1.0f;
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            float fAngle = 2f * MathF.PI * i / cem.BayonetLugs;
            Vector3 vecRadial = new(MathF.Cos(fAngle), MathF.Sin(fAngle), 0f);
            LocalFrame oLug = new((vecRadial * (fFlangeR - fOverlap)) + new Vector3(0f, 0f, fLugZ), vecRadial);
            voxPart.BoolAdd(new BaseCylinder(oLug, cem.LugProtrusionMm + fOverlap, cem.LugRadiusMm).voxConstruct());
        }

        // 4. Bus channel through the flange (the shank channel continues) — Ø1.35 to the pogo face; the
        //    monolithic anode bus rod threads it, isolated by the liner (01_01 §1.4).
        voxPart.BoolSubtract(new BaseCylinder(oFlange, fThick, cem.BoreDiameterMm / 2f).voxConstruct());

        // 5. O-ring groove — the ONE face-seal groove, an annular subtract on the capsule-side (top) face at the
        //    derived depth (CS·(1 − squeeze) = 1.344 at the ratified 24.5 %) and width (ring area / (fill·depth)),
        //    on the radii of the radome's seal land. The radome rim lands on this face as a hard datum, so the
        //    squeeze is this depth alone (02_02 §3.5 — script 52's one-term O-ring chain).
        float fDepth = ORingGrooveDepthMm(cem);
        LocalFrame oTop = new(new Vector3(0f, 0f, fShankLen + fThick - fDepth));
        Voxels voxRing = new BaseCylinder(oTop, fDepth, ORingGrooveOuterRMm(cem)).voxConstruct();
        voxRing.BoolSubtract(new BaseCylinder(oTop, fDepth, ORingGrooveInnerRMm(cem)).voxConstruct());
        voxPart.BoolSubtract(voxRing);

        return voxPart;
    }
}
