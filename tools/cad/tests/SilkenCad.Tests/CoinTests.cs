namespace SilkenCad.Tests;

// Pure-logic golden tests for the Ti-coin coupon (01_01 §6.1) — CEM parsing + the projected
// A_electrode area (01_03 §3.5). No PicoGK Library.Go: the area is analytic from the CEM (the
// j = I/A normalisation surface; the rough EAAE wetted area is unmeasurable, 01_02 §1.4). Mirrors
// AnchorTests / the firmware golden-vectors.
public class CoinTests
{
    [Fact]
    public void Cem_Parse_Defaults_To_16mm_Disc_Whole_Face()
    {
        const string strJson = """{ "kind": "ti_coin", "name": "c" }""";
        Assert.Equal("ti_coin", Cem.Kind(strJson));

        TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
        Assert.Equal(16f, cem.DiscDiameterMm);
        Assert.Equal(0f, cem.ActiveWindowDiameterMm);   // 0 ⇒ the whole face is active
    }

    [Fact]
    public void Whole_Face_16mm_Disc_Is_2_Cm2()
    {
        // π·8² = 201.06 mm² = 2.01 cm² ≈ A_electrode 2 cm² (the verify gate is ±0.1 cm²).
        TiCoinCem cem = new() { DiscDiameterMm = 16f };
        Assert.Equal(2.01, Validation.CoinAreaCm2(cem), 2);
    }

    [Fact]
    public void Defined_Window_Decouples_Area_From_The_Coupon_Diameter()
    {
        // A bigger coupon (Ø20) with an O-ring / lacquer window Ø16 keeps A = 2.01 cm² — the area
        // depends on the WINDOW, not the disc edge (the defined-area workaround).
        TiCoinCem cemWindow = new() { DiscDiameterMm = 20f, ActiveWindowDiameterMm = 16f };
        TiCoinCem cemFace = new() { DiscDiameterMm = 16f };
        Assert.Equal(Validation.CoinAreaCm2(cemFace), Validation.CoinAreaCm2(cemWindow), 6);

        // ...and that same Ø20 coupon's WHOLE face would be off-target (π·10² = 3.14 cm²) —
        // proving the window is honoured, not the disc diameter.
        TiCoinCem cemBare20 = new() { DiscDiameterMm = 20f };
        Assert.True(Validation.CoinAreaCm2(cemBare20) > 3.0);
    }

    [Fact]
    public void Cem_Parse_Reads_Alloy_Material_From_Notes()
    {
        // Alloy bake-off SKU (01_02 §2.5): each ti_coin.<alloy>.json carries its own Notes.Material,
        // which flows to the drawing title-block + metrics.json (the Stage-2 down-select traceability).
        const string strJson = """{ "kind": "ti_coin", "name": "ti_coin_7nb", "notes": { "material": "Ti-6Al-7Nb (ASTM F1295, V-free)" } }""";
        TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
        Assert.Equal("ti_coin_7nb", cem.Name);
        Assert.Equal("Ti-6Al-7Nb (ASTM F1295, V-free)", cem.Notes?.Material);
    }
}
