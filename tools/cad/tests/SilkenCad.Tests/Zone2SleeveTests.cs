// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// Pure-logic tests for the Zone-2 PEEK sleeve (Деталь 2, 01_01 §1) — CEM parse + the frozen-dim
// derivation (OD = bore + 2·wall). No PicoGK render (the hollow tube + hollow-fraction gate run in the
// `verify` CLI). Mirrors CoinTests — a simple part, so these just pin the frozen geometry.
public class Zone2SleeveTests
{
    [Fact]
    public void Cem_Parse_Reads_Kind_And_Frozen_Dims()
    {
        const string strJson =
            """{ "kind": "zone2_sleeve", "name": "s", "bore_diameter_mm": 11.0, "wall_thickness_mm": 2.0, "length_mm": 50.0 }""";
        Assert.Equal("zone2_sleeve", Cem.Kind(strJson));

        Zone2SleeveCem cem = Cem.Parse<Zone2SleeveCem>(strJson);
        Assert.Equal(11f, cem.BoreDiameterMm);   // = Zone-1 shaft Ø (press-fit), frozen 01_01 §1
        Assert.Equal(2f, cem.WallThicknessMm);   // frozen §1 — robust default, NOT CTE-limited (§4.2)
        Assert.Equal(50f, cem.LengthMm);         // axial thermal break (§4.1)
    }

    [Fact]
    public void Defaults_Are_The_Frozen_Anchor_Dims()
    {
        Zone2SleeveCem cem = new();
        Assert.Equal(11f, cem.BoreDiameterMm);
        Assert.Equal(2f, cem.WallThicknessMm);
        Assert.Equal(50f, cem.LengthMm);
    }

    [Fact]
    public void Outer_Radius_Is_Bore_Plus_Two_Walls__Wound_Ø15()
    {
        // OD = bore + 2·wall = Ø15 = the wound in the tree (CODIT <25 → DBH ≥38, 01_01 §4.2).
        Zone2SleeveCem cem = new();
        Assert.Equal(7.5f, Zone2Sleeve.OuterR(cem));          // Ø15 radius
        Assert.Equal(15f, 2f * Zone2Sleeve.OuterR(cem));      // wound diameter
    }
}
