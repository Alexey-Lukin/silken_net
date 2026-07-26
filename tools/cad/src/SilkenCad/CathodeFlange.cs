// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Zone 3 cathode flange (Деталь 3, 01_01 §1 + 02_02 §1.2) — the capsule-side anchor end. A SOLID Ti
// flange (Ø25 frozen) on the barbed Zone-3 shank that press-fits into the PEEK Zone-2 sleeve, with
// radial bayonet lugs that mate the PEEK Radome (Деталь 4, фаза 2). Reuses the §4.3 mechanical lock
// for the shank+barbs+DIN-471 groove (no duplication). Solid bodies come from ShapeKernel voxConstruct
// (gotcha #9 — never the narrow-band SDF ctor); the thin barb ridges ride the MechanicalLock split.
// Z: shank z∈[0,shankLen] (deep, into PEEK) → flange on top z∈[shankLen, shankLen+thickness] (capsule
// side). Pogo pads sit on the top face (Hard Gold = coating, not geometry); the cathode catalytic zone
// is the side/perimeter (Laccase/ZIF + PTFE-GDL, O₂ from the side under the radome bell — 02_02 §1.2).
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
        BarbDirection = -1,   // Zone-3 opposite ratchet lean (§4.3 figure)
        GrooveOffsetMm = c.GrooveOffsetMm,
        GrooveWidthMm = c.GrooveWidthMm,
        GrooveDepthMm = c.GrooveDepthMm,
    };

    public static Voxels Build(CathodeFlangeCem cem)
    {
        float fShankLen = cem.ShankLengthMm;
        float fFlangeR = cem.FlangeDiameterMm / 2f;
        float fThick = cem.FlangeThicknessMm;

        // 1. Barbed Zone-3 shank (reuse §4.3 lock): solid Ø + barbs + DIN-471 groove + bus channel, z∈[0,shankLen].
        Voxels voxPart = MechanicalLock.Build(ShankCem(cem));

        // 2. Solid Ø25 flange disc on top — a true filled cylinder (gotcha #9: voxConstruct, NOT the SDF ctor).
        LocalFrame oFlange = new(new Vector3(0f, 0f, fShankLen));
        voxPart.BoolAdd(new BaseCylinder(oFlange, fThick, fFlangeR).voxConstruct());

        // 3. Bayonet lugs — radial pins evenly spaced around the flange rim (mate the Радом socket, фаза 2).
        //    Each pin's local-Z = the radial outward direction; it overlaps the rim by fOverlap to fuse.
        float fLugZ = fShankLen + (fThick / 2f);
        const float fOverlap = 1.0f;
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            float fAngle = 2f * MathF.PI * i / cem.BayonetLugs;
            Vector3 vecRadial = new(MathF.Cos(fAngle), MathF.Sin(fAngle), 0f);
            LocalFrame oLug = new((vecRadial * (fFlangeR - fOverlap)) + new Vector3(0f, 0f, fLugZ), vecRadial);
            voxPart.BoolAdd(new BaseCylinder(oLug, cem.LugProtrusionMm + fOverlap, cem.LugRadiusMm).voxConstruct());
        }

        // 4. Bus channel through the flange (the shank channel continues) — Ø1.3 to the pogo face; the
        //    monolithic anode bus rod threads it, isolated by the liner (01_01 §1.4).
        voxPart.BoolSubtract(new BaseCylinder(oFlange, fThick, cem.BoreDiameterMm / 2f).voxConstruct());

        // 5. O-ring groove — annular subtract on the capsule-side (top) face (mate the Радом O-ring, CS 1.78).
        LocalFrame oTop = new(new Vector3(0f, 0f, fShankLen + fThick - cem.ORingGrooveDepthMm));
        float fGrooveOuter = fFlangeR - 1.5f;
        Voxels voxRing = new BaseCylinder(oTop, cem.ORingGrooveDepthMm, fGrooveOuter).voxConstruct();
        voxRing.BoolSubtract(new BaseCylinder(oTop, cem.ORingGrooveDepthMm, fGrooveOuter - cem.ORingGrooveWidthMm).voxConstruct());
        voxPart.BoolSubtract(voxRing);

        return voxPart;
    }
}
