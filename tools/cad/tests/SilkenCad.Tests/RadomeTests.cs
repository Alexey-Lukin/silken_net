// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Text.Json;

namespace SilkenCad.Tests;

// Pure-logic golden tests for the PEEK Radome (Деталь 4, 02_01 §5.2) — CEM parse + bayonet mate-fit
// math + the RF wall band + the rim boss / seal land the capsule seal stands on (00_07 HW.33 branch (а),
// applied 2026-09-14). No PicoGK Library.Go (the hollow-shell / bell / seal-land render gates run in
// `verify`). Mirrors CathodeFlangeTests.
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
        Assert.True(cem.CavityHeightMm >= 12f);    // OUR working floor on the CEM dim — NOT antenna↔Ti (that is cavityH − lockGrooveZ − t/2) and NOT the canon ≥8 (02_01 §5.3)
        Assert.True(cem.BellRiseMm >= 3f);         // anti-overgrowth shield (01_04 §5.5)
    }

    [Fact]
    public void Socket_Admits_The_Деталь3_Lug_With_Clearance()
    {
        // Bayonet mate-fit: the socket pocket (lug + clearance) must exceed the Деталь-3 lug, and the
        // radome's mate lug-radius must equal the flange's (same lug — Деталь 3 ↔ Деталь 4). The flange
        // now reads the socket clearance and the gland spec too (its groove is positioned off them), so the
        // three shared fields are pinned equal here — one home would be better, and the precedent is the lug.
        RadomeCem cem = new();
        CathodeFlangeCem flange = new();
        Assert.True(cem.LugRadiusMm + cem.SlotClearanceMm > cem.LugRadiusMm, "socket must clear the lug");
        Assert.Equal(flange.LugRadiusMm, cem.LugRadiusMm);
        Assert.Equal(flange.SlotClearanceMm, cem.SlotClearanceMm);
        Assert.Equal(flange.ORing, cem.ORing);   // record equality: cord · squeeze · fill, all three
    }

    [Fact]
    public void Wall_Is_Within_The_RF_Band()
    {
        // 02_01 §5.2: PEEK wall 1.5–2.0 mm (RF loss vs strength). ⛔ The wall is NOT what closes the seal any
        // more — the assert that stood here (`groove width ≤ wall`) asked whether a GROOVE fits the WALL and
        // never whether the RING fits the GROOVE; the seal-land pins below ask the second question.
        RadomeCem cem = new();
        Assert.InRange(cem.WallThicknessMm, 1.5f, 2.0f);
    }

    // ── Branch (а): the ring fits its GLAND, and the land is wider than the gland — STRICT, never `<=` ──
    // A gland the ring exactly fills (fill = 1) has nowhere to put the elastomer it displaces, and a land exactly
    // as wide as the groove backs the ring only at perfect socket alignment. Both are the zero-margin states
    // the old `<=` used to bless. MUTATION: `GlandFill = 1f` reds the first assert; dropping the `2·clearance`
    // from Radome.SealBandMm reds the second.
    [Fact]
    public void The_Ring_Fits_Its_Gland_And_The_Land_Is_Wider_Than_The_Gland__Strictly()
    {
        RadomeCem cem = new();
        Assert.True(cem.ORing.GlandFill < 1f, "a gland the ring fills completely is not a gland");
        Assert.True(cem.ORing.RingAreaMm2 < cem.ORing.WidthMm * cem.ORing.DepthMm - 1e-4f,
            "the ring section must be strictly smaller than the groove section");
        Assert.Equal(cem.ORing.RingAreaMm2, cem.ORing.WidthMm * cem.ORing.DepthMm * cem.ORing.GlandFill, 4);
        Assert.True(Radome.SealBandMm(cem) > cem.ORing.WidthMm, "the seal land must be wider than the groove it closes");
        Assert.Equal(2f * cem.SlotClearanceMm, Radome.SealBandMm(cem) - cem.ORing.WidthMm, 4);
    }

    // The seal land is CONTINUOUS: every socket cut stays in the OUTER band of the boss, the land is the INNER
    // band and is the full seal band wide, and the pocket stops short of the dome OD (a skin, never a breach).
    // MUTATION: clip the socket at the inner wall instead of the land's outer edge ⇒ the first assert reds.
    [Fact]
    public void Entry_Slots_Stay_In_The_Outer_Band__The_Seal_Land_Is_Uncut()
    {
        RadomeCem cem = new();
        Assert.True(Radome.SocketPocketInnerRMm(cem) >= Radome.SealLandOuterRMm(cem), "a socket cut must not enter the seal land");
        Assert.True(Radome.SocketPocketOuterRMm(cem) < cem.DomeDiameterMm / 2f, "the pocket must stop short of the dome OD");
        Assert.True(Radome.SocketSkinMm(cem) > 0f);
        Assert.Equal(Radome.SealBandMm(cem), Radome.SealLandOuterRMm(cem) - Radome.SealLandInnerRMm(cem), 4);
        Assert.Equal(Radome.BossRadialMm(cem), (cem.DomeDiameterMm / 2f) - Radome.SealLandInnerRMm(cem), 4);
        Assert.Equal(15.57f, Radome.RimCavityDiameterMm(cem), 2);   // the ceiling handed to HW.9 (every term a minimum)
    }

    // The rim is FLAT: the shipped manifests carry no groove key (one has no slot since 2026-09-14 and would
    // EVAPORATE on parse, gotcha 0b) and DO carry the gland spec the land is sized from; the record exposes no
    // groove property, so the cut cannot come back by a stale default.
    [Theory]
    [InlineData("radome.json")]
    [InlineData("cathode_flange.json")]
    public void The_Shipped_Manifests_Declare_The_Gland_And_No_Groove_Key(string strFile)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(CemFixtures.Dir(), strFile)));
        Assert.False(doc.RootElement.TryGetProperty("o_ring_groove_depth_mm", out _), $"{strFile} still carries the retired counter-groove key");
        Assert.False(doc.RootElement.TryGetProperty("o_ring_groove_width_mm", out _));
        Assert.True(doc.RootElement.TryGetProperty("o_ring", out JsonElement oRing));
        foreach (string key in new[] { "cs_mm", "squeeze", "gland_fill" })
            Assert.True(oRing.TryGetProperty(key, out _), $"{strFile}: o_ring.{key} missing");
        Assert.Null(typeof(RadomeCem).GetProperty("ORingGrooveDepthMm"));
        Assert.Null(typeof(CathodeFlangeCem).GetProperty("ORingGrooveDepthMm"));
    }

    // The two SHIPPED manifests carry ONE gland spec and one socket band — the record-default equality above
    // proves the defaults, this proves the files: a `gland_fill` edited on one manifest only would leave the
    // flange cutting a groove the radome's land no longer backs. (Script 52 refuses the same drift at runtime.)
    [Fact]
    public void The_Shipped_Flange_And_Radome_Carry_One_Gland_Spec_And_One_Socket_Band()
    {
        RadomeCem radome = Cem.Parse<RadomeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "radome.json")));
        CathodeFlangeCem flange = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json")));
        Assert.Equal(flange.ORing, radome.ORing);
        Assert.Equal(flange.LugRadiusMm, radome.LugRadiusMm);
        Assert.Equal(flange.SlotClearanceMm, radome.SlotClearanceMm);
        Assert.Equal(flange.FlangeDiameterMm, radome.DomeDiameterMm);
    }

    // 🔗 The C#↔Python crossing, pinned from THIS side: what Radome.* / CathodeFlange.* derive from the shipped
    // manifests must equal what script 52 wrote to its cache from the same manifest fields — the gland (depth,
    // ring section, width at the shipped fill), the rim-cavity ceiling and the applied radii. MUTATION: change a
    // formula on either side ⇒ reds; change a manifest field without re-running 52 ⇒ reds. (52's own half of the
    // pin is at runtime: it reads the `o_ring` block and refuses to run if it differs from its constants.)
    [Fact]
    public void Rim_Boss_And_Gland_Derivation_Matches_Script_52_Cache()
    {
        RadomeCem cem = Cem.Parse<RadomeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "radome.json")));
        CathodeFlangeCem flange = Cem.Parse<CathodeFlangeCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "cathode_flange.json")));
        using var cache = JsonDocument.Parse(File.ReadAllText(CemFixtures.ZStackCache()));

        JsonElement gland = cache.RootElement.GetProperty("gland_geometry");
        Near(gland.GetProperty("depth_mm").GetDouble(), cem.ORing.DepthMm, 1e-3);
        Near(gland.GetProperty("ring_area_mm2").GetDouble(), cem.ORing.RingAreaMm2, 1e-3);
        string strFill = $"{(int)MathF.Round(cem.ORing.GlandFill * 100f)}%";
        Near(gland.GetProperty("required_width_mm").GetProperty(strFill).GetDouble(), cem.ORing.WidthMm, 1e-3);

        JsonElement boss = cache.RootElement.GetProperty("rim_boss_radial_budget");
        Near(boss.GetProperty("design_to_mm").GetDouble(), Radome.RimCavityDiameterMm(cem), 5e-3);

        JsonElement applied = cache.RootElement.GetProperty("applied_gland");
        Near(applied.GetProperty("flange_groove_depth_mm").GetDouble(), CathodeFlange.ORingGrooveDepthMm(flange), 1e-3);
        Near(applied.GetProperty("flange_groove_width_mm").GetDouble(), CathodeFlange.ORingGrooveWidthMm(flange), 1e-3);
        Near(applied.GetProperty("flange_groove_r_mm")[0].GetDouble(), CathodeFlange.ORingGrooveInnerRMm(flange), 1e-3);
        Near(applied.GetProperty("flange_groove_r_mm")[1].GetDouble(), CathodeFlange.ORingGrooveOuterRMm(flange), 1e-3);
        Near(applied.GetProperty("radome_seal_land_r_mm")[0].GetDouble(), Radome.SealLandInnerRMm(cem), 1e-3);
        Near(applied.GetProperty("radome_seal_land_r_mm")[1].GetDouble(), Radome.SealLandOuterRMm(cem), 1e-3);
        Near(applied.GetProperty("socket_pocket_r_mm")[0].GetDouble(), Radome.SocketPocketInnerRMm(cem), 1e-3);
        Near(applied.GetProperty("socket_pocket_r_mm")[1].GetDouble(), Radome.SocketPocketOuterRMm(cem), 1e-3);
        Near(applied.GetProperty("rim_cavity_mm").GetDouble(), Radome.RimCavityDiameterMm(cem), 5e-3);
    }

    private static void Near(double dExpected, double dActual, double dTol)
        => Assert.InRange(dActual, dExpected - dTol, dExpected + dTol);
}
