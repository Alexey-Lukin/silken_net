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
        // At the bayonet datum the rim lands 6.42 mm off the O-ring target, and the cavity is pulled onto
        // the flange ⇒ antenna↔Ti = 8 mm < 12. These are the Z-stack findings (HW.8), NOT a code bug.
        AnchorAssemblyCem cem = new();
        Assert.Equal(6.424, Assembly.BayonetZMismatchMm(cem), 3);   // |12 − (17 + 1.424)|
        Assert.Equal(8.0f, Assembly.RfClearanceMm(cem), 3);          // (12 + 13) − 17
        Assert.True(Assembly.RfClearanceMm(cem) < cem.RfClearanceMinMm, "RF clearance must fall below the 12 mm floor here");
    }

    [Fact]
    public void Inboard_Candidate_Pulls_The_Lug_Tips_Within_Ø25()
    {
        // The inboard MATE-Ø candidate clamps protrusion to 0 ⇒ lug tip = flangeR = Ø25 (no protrusion).
        AnchorAssemblyCem cem = new() { Flange = new CathodeFlangeCem { LugProtrusionMm = 0f } };
        Assert.Equal(12.5f, Assembly.LugTipRadiusMm(cem));    // Ø25 — within the dome OD
    }
}
