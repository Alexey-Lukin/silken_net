namespace SilkenCad.Tests;

// Pure-logic golden tests for the PEEK Radome (Деталь 4, 02_01 §5.2) — CEM parse + bayonet mate-fit
// math + the RF wall band. No PicoGK Library.Go (the hollow-shell / bell render gates run in `verify`).
// Mirrors CathodeFlangeTests.
public class RadomeTests
{
    [Fact]
    public void Cem_Parse_Reads_Frozen_Dims()
    {
        const string strJson = """{ "kind": "radome", "name": "r" }""";
        Assert.Equal("radome", Cem.Kind(strJson));

        RadomeCem cem = Cem.Parse<RadomeCem>(strJson);
        Assert.Equal(25f, cem.DomeDiameterMm);     // frozen (= Zone-3 flange Ø)
        Assert.Equal(3, cem.BayonetLugs);
        Assert.True(cem.CavityHeightMm >= 12f);    // antenna↔Ti RF clearance (02_01 §5.3)
        Assert.True(cem.BellRiseMm >= 3f);         // anti-overgrowth shield (01_04 §5.5)
    }

    [Fact]
    public void Socket_Admits_The_Деталь3_Lug_With_Clearance()
    {
        // Bayonet mate-fit: the socket pocket (lug + clearance) must exceed the Деталь-3 lug, and the
        // radome's mate lug-radius must equal the flange's (same lug — Деталь 3 ↔ Деталь 4).
        RadomeCem cem = new();
        Assert.True(cem.LugRadiusMm + cem.SlotClearanceMm > cem.LugRadiusMm, "socket must clear the lug");
        Assert.Equal(new CathodeFlangeCem().LugRadiusMm, cem.LugRadiusMm);
    }

    [Fact]
    public void Wall_Is_Within_The_RF_Band()
    {
        // 02_01 §5.2: PEEK wall 1.5–2.0 mm (RF loss vs strength); O-ring groove width must fit the wall.
        RadomeCem cem = new();
        Assert.InRange(cem.WallThicknessMm, 1.5f, 2.0f);
        Assert.True(cem.ORingGrooveWidthMm <= cem.WallThicknessMm, "O-ring groove must fit within the wall");
    }
}
