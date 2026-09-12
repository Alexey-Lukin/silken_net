// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad.Tests;

// Pure-logic press-fit mate-audit tests for the full axial stack (Zone 1↔2↔3↔4, 01_01 §1+§3) — CEM parse
// + the interference / insertion / span maths. No PicoGK render (the merged STL + interference volumes run
// in the `verify` CLI). These ASSERT the known findings, so the stack stays an honest audit: F1 (the
// Ø9-in-Ø11 clearance) and F2 (insertion budget) bite the regression if a dim drifts. Mirrors AssemblyTests.
public class AxialStackTests
{
    [Fact]
    public void Cem_Parse_Reads_Kind_And_Nested_Part_Defaults()
    {
        const string strJson = """{ "kind": "anchor_axial_stack", "name": "x" }""";
        Assert.Equal("anchor_axial_stack", Cem.Kind(strJson));

        AnchorAxialStackCem cem = Cem.Parse<AnchorAxialStackCem>(strJson);
        Assert.Equal(11f, cem.Zone1.OuterDiameterMm);          // nested Zone-1 frozen dim inherited
        Assert.Equal(11f, cem.Zone2.BoreDiameterMm);           // nested Zone-2 frozen dim inherited
        Assert.Equal(9f, cem.Capsule.Flange.ShankDiameterMm);  // nested Деталь-3 shank PLACEHOLDER (HW.8)
        Assert.Equal(30f, cem.Zone1InsertionMm);
    }

    [Fact]
    public void Zone1_Sleeve_Is_Nominal_Line_To_Line__Press_Fit_Band_Is_Bench()
    {
        // Anode Ø11 into sleeve bore Ø11 ⇒ 0 nominal interference. The real +interference is the H7/s6
        // tolerance band (tens of µm, ISO 286), set on the bench — not in the nominal CEM (01_01 §3).
        AnchorAxialStackCem cem = new();
        Assert.Equal(0f, AxialStack.Zone1SleeveInterferenceMm(cem), 3);
    }

    [Fact]
    public void Sleeve_Zone3_Is_A_Clearance_Not_A_Press_Fit__F1()
    {
        // F1 (the key finding): Zone-3 shank Ø9 (placeholder) in bore Ø11 ⇒ (9−11)/2 = −1.0 mm = 1 mm
        // clearance per side. A press-fit needs +interference (tens of µm, ISO 286); this is off by ~50× → HW.8.
        AnchorAxialStackCem cem = new();
        Assert.Equal(-1.0f, AxialStack.SleeveZone3InterferenceMm(cem), 3);
        Assert.True(AxialStack.SleeveZone3InterferenceMm(cem) < 0, "Zone-3 shank must NOT press-fit at the placeholder Ø");
    }

    [Fact]
    public void Insertion_Budget_Is_Positive__Shanks_Do_Not_Collide__F2()
    {
        // F2: bore 50 − (Zone-1 insert 30 + Zone-3 shank 14) = 6 mm clearance between the two shank ends.
        AnchorAxialStackCem cem = new();
        Assert.Equal(6f, AxialStack.InsertionBudgetMm(cem), 3);
        Assert.True(AxialStack.InsertionBudgetMm(cem) >= 0, "the two shanks must not collide inside the sleeve bore");
    }

    [Fact]
    public void Z_Layout_Stacks_From_The_Tree_Side_Up()
    {
        // Datum: anode bottom z=0. Sleeve bottom = Zone-1 top (40) − insertion (30) = 10; sleeve top = 60;
        // capsule lifts so the flange shank (14) inserts into the sleeve top ⇒ lift = 60 − 14 = 46;
        // embedded span = sleeve top 60 + flange thickness 3 = 63 (radome bayonets above, over the bark).
        AnchorAxialStackCem cem = new();
        Assert.Equal(10f, AxialStack.SleeveBottomZMm(cem), 3);
        Assert.Equal(60f, AxialStack.SleeveTopZMm(cem), 3);
        Assert.Equal(46f, AxialStack.CapsuleLiftZMm(cem), 3);
        Assert.Equal(63f, AxialStack.OverallStackLengthMm(cem), 3);
    }

    [Fact]
    public void Legacy_Hollow_Bore_Falls_Back__Anode_Bore_Ge_Flange_Bore()
    {
        // Back-compat: a CEM with no monolithic rod (BusRodDiameterMm==0) keeps the old continuity check —
        // the anode Ø1.6 bore ≥ the flange Ø1.35 bore (01_01 §1).
        AnchorAxialStackCem cem = new();
        Assert.True(AxialStack.BusRodClears(cem));
    }

    [Fact]
    public void Monolithic_Bus_Rod_Clears_Cathode_Channel__Rod_Plus_2Liner_Lt_Bore()
    {
        // F3 (01_01 §1.4): the solid rod + its insulation liner must fit the cathode channel WITH room.
        // rod 1.0 + 2·liner 0.15 = 1.30 < channel 1.35 ⇒ clears by 50 µm diametral.
        AnchorAxialStackCem cem = new()
        {
            Zone1 = new AnchorCem { BusRodDiameterMm = 1.0f },
            Capsule = new AnchorAssemblyCem { Flange = new CathodeFlangeCem { BusLinerThicknessMm = 0.15f } },
        };
        Assert.True(AxialStack.BusRodClears(cem));
    }

    // The state the gate used to bless, and the reason it is strict now: at the pre-verdict channel Ø1.30
    // the stack sums to EXACTLY the bore. `<=` called that a pass — a true statement about the sum and a
    // false one about the assembly, since a tube whose outer Ø equals the bore does not go in. The
    // clearance verdict (00_07 HW.34) made zero an unintended state, so it must now FAIL.
    [Fact]
    public void Zero_Nominal_Clearance_Is_Not_A_Pass__The_Pre_Verdict_Channel()
    {
        AnchorAxialStackCem cem = new()
        {
            Zone1 = new AnchorCem { BusRodDiameterMm = 1.0f },
            Capsule = new AnchorAssemblyCem
            {
                Flange = new CathodeFlangeCem { BusLinerThicknessMm = 0.15f, BoreDiameterMm = 1.3f },
            },
        };
        Assert.False(AxialStack.BusRodClears(cem));
    }

    // ── F4: the liner covers the channel LENGTHWISE — the axis F3 declares itself blind to ──

    [Fact]
    public void Liner_Covers_The_Channel_End_To_End__And_Protrudes_Below_The_Shank_Face()
    {
        // ⚖️ 2026-09-12 (00_07 HW.34): the tube spans the whole channel — ground = the perimeter of
        // CATHODE METAL, which surrounds the rod over the entire channel INCLUDING the top face — and
        // its lower end reaches 1.0 mm further, into the PEEK gap.
        AnchorAxialStackCem cem = Fix();
        Assert.Equal(45f, AxialStack.LinerBottomZMm(cem), 3);   // shank face 46 − 1.0 protrusion
        Assert.Equal(63f, AxialStack.LinerTopZMm(cem), 3);      // flush with the pogo face
        Assert.Equal(18f, AxialStack.LinerLengthMm(cem), 3);    // channel 17 + protrusion 1
        Assert.True(AxialStack.LinerCoversChannel(cem));
    }

    // ⛔ The state F3 cannot see, and the reason F4 exists: a tube SHORTER than the channel still
    // satisfies rod + 2·liner < bore — a statement about the DIAMETER — while leaving bare cathode
    // metal against the bus at one end. Mutation of the protrusion alone must not rescue it.
    [Fact]
    public void A_Liner_Shorter_Than_The_Channel_Passes_F3_And_Must_Fail_F4()
    {
        AnchorAxialStackCem cem = Fix();
        Assert.True(AxialStack.BusRodClears(cem));              // diameter: still fine

        // A flange whose channel is LONGER than the tube the protrusion accounts for: lengthen the
        // shank without lengthening the liner, i.e. exactly the drift this gate is for.
        AnchorAxialStackCem shortLiner = Fix(protrusionMm: -2f);
        Assert.True(AxialStack.BusRodClears(shortLiner));
        Assert.False(AxialStack.LinerCoversChannel(shortLiner));
    }

    [Fact]
    public void No_Liner_Declared__F4_Is_Vacuously_True_Not_Silently_False()
    {
        // A CEM with no liner at all (thickness 0) has no tube to place, so F4 must not manufacture a
        // finding about one. ⛔ The declared ceiling, stated in the gate itself: this is the ONLY
        // branch where a green F4 says nothing about coverage.
        AnchorAxialStackCem cem = Fix(linerMm: 0f);
        Assert.True(AxialStack.LinerCoversChannel(cem));
    }

    private static AnchorAxialStackCem Fix(float linerMm = 0.15f, float protrusionMm = 1.0f)
        => new()
        {
            Zone1 = new AnchorCem { BusRodDiameterMm = 1.0f },
            Capsule = new AnchorAssemblyCem
            {
                Flange = new CathodeFlangeCem
                {
                    BusLinerThicknessMm = linerMm,
                    BusLinerProtrusionMm = protrusionMm,
                },
            },
        };

    [Fact]
    public void Monolithic_Bus_Rod_Pinched__Rod_Plus_Liner_Exceeds_Channel()
    {
        // rod 1.2 + 2·liner 0.15 = 1.50 > channel 1.35 ⇒ pinched (F3 ⚠).
        AnchorAxialStackCem cem = new()
        {
            Zone1 = new AnchorCem { BusRodDiameterMm = 1.2f },
            Capsule = new AnchorAssemblyCem { Flange = new CathodeFlangeCem { BusLinerThicknessMm = 0.15f } },
        };
        Assert.False(AxialStack.BusRodClears(cem));
    }
}
