// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// Pure-logic mate-audit tests for the capsule-end assembly (Деталь 3 ↔ Деталь 4, 02_02 §4) — CEM parse +
// the bayonet datum / Z-stack / MATE-Ø maths. No PicoGK render (the merged STL + interference run in the
// `verify` CLI). These ASSERT the known mismatch numbers, so the assembly stays an honest audit: if a
// generator changes the dims, the expected mismatch moves and the regression bites. Mirrors RadomeTests.
public class AssemblyTests
{
    [Fact]
    public void Cem_Parse_Reads_Kind_And_Nested_Part_Defaults()
    {
        const string strJson = """{ "kind": "anchor_assembly", "name": "a", "mate_strategy": "skirt" }""";
        Assert.Equal("anchor_assembly", Cem.Kind(strJson));

        AnchorAssemblyCem cem = Cem.Parse<AnchorAssemblyCem>(strJson);
        Assert.Equal("skirt", cem.MateStrategy);
        Assert.Equal(25f, cem.Flange.FlangeDiameterMm);   // nested Деталь-3 frozen dim inherited
        Assert.Equal(25f, cem.Radome.DomeDiameterMm);     // nested Деталь-4 frozen dim inherited
        Assert.Equal(3.5f, cem.Radome.LockGrooveZMm);
    }

    [Fact]
    public void Mate_Strategy_Defaults_To_The_Asis_Audit()
        => Assert.Equal("asis", new AnchorAssemblyCem().MateStrategy);

    [Fact]
    public void Bayonet_Datum_Lifts_The_Radome_LockGroove_Onto_The_Flange_Lugs()
    {
        // Datum: radome rises so its lock-groove (z=3.5 from its rim) meets the flange lugs (z=15.5).
        AnchorAssemblyCem cem = new();
        Assert.Equal(15.5f, Assembly.FlangeLugZMm(cem));      // shankLen 14 + thickness 3 / 2
        Assert.Equal(17.0f, Assembly.FlangeTopZMm(cem));      // shankLen 14 + thickness 3
        Assert.Equal(12.0f, Assembly.RadomeLiftZMm(cem));     // 15.5 − 3.5
    }

    [Fact]
    public void Lug_Tips_Protrude_Past_The_Dome_Ø__MATE_Ø_Conflict()
    {
        // Lug tip reaches R = flangeR + protrusion = 14.5 (Ø29), past the Ø25 dome; and the Ø25 disc fouls
        // the Ø(25−2·wall)=Ø21 cavity ⇒ radial gap −2.0. The core MATE-Ø finding (HW.17).
        AnchorAssemblyCem cem = new();
        Assert.Equal(14.5f, Assembly.LugTipRadiusMm(cem));    // Ø29
        Assert.True(Assembly.LugTipRadiusMm(cem) > cem.Radome.DomeDiameterMm / 2f, "lugs must exceed the dome OD");
        Assert.Equal(-2.0f, Assembly.MateRadialGapMm(cem), 3);
    }

    [Fact]
    public void Z_Stack_Is_Un_Reconciled__Bayonet_Z_And_RF_Findings()
    {
        // At the bayonet datum the rim lands 5.0 mm BELOW the flange top face it must seal on, and the cavity
        // is pulled onto the flange ⇒ antenna↔Ti = 8 mm < 12. These are the Z-stack findings (HW.8), NOT a
        // code bug. ⚖️ This read 6.424 (= 5.0 + the 1.424 face gap) until branch (а) was applied 2026-09-14:
        // the gap term LEFT the chain (rim = hard datum on the face), the two remaining terms did not move.
        AnchorAssemblyCem cem = new();
        Assert.Equal(5.0, Assembly.BayonetZMismatchMm(cem), 3);     // |12 − 17|
        Assert.Equal(8.0f, Assembly.RfClearanceMm(cem), 3);          // (12 + 13) − 17
        // ⛔ "below OUR 12", not "below canon's floor": 02_01 §5.3 asks ≥ 8 (10-15 desirable, HFSS below
        // 10), so 8.0 does not violate canon — which number is acceptance a mock-up measurement settles
        // (⚖️ 2026-09-17, 02_01 §5.3). This pin regresses the ARITHMETIC against the CEM constant, nothing more. [2026-09-11]
        Assert.True(Assembly.RfClearanceMm(cem) < cem.RfClearanceMinMm, "RF clearance must fall below the CEM's 12 mm working floor here");
    }

    [Fact]
    public void The_Bayonet_Z_Mismatch_Is_The_Lug_Z_Deficit__Two_Positive_Terms_And_A_Face_Gap_That_Is_Zero_Under_Branch_A()
    {
        // The finding this pins is structural, not numeric: the mismatch decomposes into t/2 + lockGrooveZ,
        // both terms positive, so no assignment of the frozen dims reaches zero — and it equals the LUG's Z
        // deficit exactly, which is what names the lever (00_07 HW.33 MATE-Ø). ⚖️ It used to be THREE terms:
        // the O-ring face gap (1.424) was the third. Under branch (а), applied 2026-09-14, the radome rim is a
        // HARD DATUM on the flange top face and the squeeze is the flange groove's depth, so that term is ZERO
        // BY CONSTRUCTION — said here, not recomputed silently: the mismatch fell 6.42 → 5.0 because a term left
        // the chain (the field is gone from AnchorAssemblyCem), not because a value moved. 02_02 §4.4 says the same.
        AnchorAssemblyCem cem = new();
        float fClosedForm = (cem.Flange.FlangeThicknessMm / 2f) + cem.Radome.LockGrooveZMm;
        Assert.Equal(fClosedForm, Assembly.BayonetZMismatchMm(cem), 3);
        Assert.Equal(Assembly.RequiredLugZMm(cem) - Assembly.FlangeLugZMm(cem), Assembly.BayonetZMismatchMm(cem), 3);
        Assert.Equal(20.5f, Assembly.RequiredLugZMm(cem), 3);       // = flange top 17 + lockGrooveZ 3.5, exactly lockGrooveZ over the sealing face (02_02 §4.4)
        Assert.Null(typeof(AnchorAssemblyCem).GetProperty("ORingGapMm"));   // the gap is not a parameter of the mate any more

        // Shank cancels in BOTH equations — the mate maths cannot be moved by the one dim HW.8 calls a
        // placeholder, so a shank reconcile is not a Z-reconcile.
        AnchorAssemblyCem cemLong = cem with { Flange = cem.Flange with { ShankLengthMm = 22f } };
        Assert.Equal(Assembly.BayonetZMismatchMm(cem), Assembly.BayonetZMismatchMm(cemLong), 3);
        Assert.Equal(Assembly.RfClearanceMm(cem), Assembly.RfClearanceMm(cemLong), 3);

        // The two "independent" equations share a conservation law: lowering lockGrooveZ or t pays into
        // both at once, cavityH pays into RF alone. (It read `cavityH + gap` with the gap term.)
        Assert.Equal(cem.Radome.CavityHeightMm,
                     Assembly.RfClearanceMm(cem) + Assembly.BayonetZMismatchMm(cem), 3);
    }

    // ── Branch (а) seal mate: the flange groove sits INSIDE the radome's seal land with one slot clearance of
    //    land on EACH side, strictly. A margin of exactly zero (groove edge = land edge) fails: with the radome
    //    one socket clearance off-centre the ring would then be unbacked on one side. ──
    // MUTATION: drop either `− SlotClearanceMm` from CathodeFlange.ORingGrooveOuterRMm ⇒ the outer margin reads
    // 0 (reds `> 0`) or 0.6 (reds the equality); drop the `2·clearance` from Radome.SealBandMm ⇒ the inner reds.
    [Fact]
    public void Seal_Land_Backs_The_Groove_With_One_Slot_Clearance_On_Each_Side()
    {
        AnchorAssemblyCem cem = new();
        Assert.True(Assembly.SealLandBacksTheGroove(cem));
        Assert.True(Assembly.SealLandMarginInnerMm(cem) > 0f);
        Assert.True(Assembly.SealLandMarginOuterMm(cem) > 0f);
        Assert.Equal(cem.Radome.SlotClearanceMm, Assembly.SealLandMarginInnerMm(cem), 3);
        Assert.Equal(cem.Radome.SlotClearanceMm, Assembly.SealLandMarginOuterMm(cem), 3);

        // Frozen dims, spelled out so a reader can check them against 02_02 §3.5: land r 7.785–10.7, groove r 8.085–10.4.
        Assert.Equal(7.785f, Radome.SealLandInnerRMm(cem.Radome), 3);
        Assert.Equal(10.7f, Radome.SealLandOuterRMm(cem.Radome), 3);
        Assert.Equal(8.085f, CathodeFlange.ORingGrooveInnerRMm(cem.Flange), 3);
        Assert.Equal(10.4f, CathodeFlange.ORingGrooveOuterRMm(cem.Flange), 3);

        // The zero-margin state, built on purpose: a radome socket clearance twice the flange's puts the land's
        // outer edge EXACTLY on the groove's outer edge (12.5 − 1.5 − 2c = 12.5 − 1.5 − c − c). The inner margin
        // is still positive there, so only the strict `> 0` on the outer side refuses it — `>=` would pass it.
        AnchorAssemblyCem flush = cem with { Radome = cem.Radome with { SlotClearanceMm = 2f * cem.Flange.SlotClearanceMm } };
        Assert.Equal(0f, Assembly.SealLandMarginOuterMm(flush), 3);
        Assert.True(Assembly.SealLandMarginInnerMm(flush) > 0f);
        Assert.False(Assembly.SealLandBacksTheGroove(flush));
    }

    [Fact]
    public void Inboard_Candidate_Pulls_The_Lug_Tips_Within_Ø25()
    {
        // The inboard MATE-Ø candidate clamps protrusion to 0 ⇒ lug tip = flangeR = Ø25 (no protrusion).
        AnchorAssemblyCem cem = new() { Flange = new CathodeFlangeCem { LugProtrusionMm = 0f } };
        Assert.Equal(12.5f, Assembly.LugTipRadiusMm(cem));    // Ø25 — within the dome OD
    }
}
