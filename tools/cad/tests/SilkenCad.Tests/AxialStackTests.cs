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
        // Anode Ø11 into sleeve bore Ø11 ⇒ 0 nominal interference. The real +interference is the press-fit
        // tolerance band (tens of µm; no ISO 286 table class is ratified — the band is solved from the Lamé window,
        // ⚖️ 2026-09-18, 00_07 HW.3, only its inputs open), set on the bench — not in the nominal CEM (01_01 §3).
        AnchorAxialStackCem cem = new();
        Assert.Equal(0f, AxialStack.Zone1SleeveInterferenceMm(cem), 3);
    }

    [Fact]
    public void Sleeve_Zone3_Is_A_Clearance_Not_A_Press_Fit__F1()
    {
        // F1 (the key finding): Zone-3 shank Ø9 (placeholder) in bore Ø11 ⇒ (9−11)/2 = −1.0 mm = 1 mm
        // clearance per side. A press-fit needs +interference (tens of µm, from the Lamé window — 00_07 HW.3); this is
        // off by ~50× → HW.8.
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
        // overall stack length = sleeve top 60 + flange thickness 3 = 63 (anode bottom → flange top). The embedded
        // depth is 60, not 63: the flange seats on the bark, so its UNDERSIDE is the bark line (⚖️ HW.33
        // 2026-09-18); the radome bayonets above, over the bark.
        AnchorAxialStackCem cem = new();
        Assert.Equal(10f, AxialStack.SleeveBottomZMm(cem), 3);
        Assert.Equal(60f, AxialStack.SleeveTopZMm(cem), 3);
        Assert.Equal(46f, AxialStack.CapsuleLiftZMm(cem), 3);
        Assert.Equal(63f, AxialStack.OverallStackLengthMm(cem), 3);
    }

    [Fact]
    public void A_Stack_Whose_Zone1_Declares_No_Rod_Fails_F3__Nothing_To_Check_The_Channel_Against()
    {
        // F3 checks the rod against the cathode channel (01_01 §1.4); a Zone 1 without a rod leaves nothing to
        // check, so F3 must not pass vacuously on an empty rod. (The rod is the welded WIRE — it starts at the
        // anode's top face and never runs through the printed part, ⚖️ 2026-09-18, 00_07 HW.1; not asserted here.)
        AnchorAxialStackCem cem = new();
        Assert.Equal(0f, cem.Zone1.BusRodDiameterMm);
        Assert.False(AxialStack.BusRodClears(cem));
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

    // ── Zone-1 insertion vs the window its own lock admits (00_07 HW.26 G1) ──

    // ⛔ A DETECTOR pin, never a cement: every insertion below is SET, never read from the stack default — so the
    //    day G1 moves `zone1_insertion_mm` into the window this stays green and only the verify ⚠ goes quiet.
    // MUTATION: drop either comparison in AxialStack.Zone1InsertionConflict ⇒ its row reds.
    [Fact]
    public void An_Insertion_Outside_The_Zone1_Lock_Window_Is_Reported_By_Name()
    {
        MechanicalLockCem lockCem = Cem.Parse<MechanicalLockCem>(
            File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone1.json")));
        MechanicalLock.InsertionWindow w = MechanicalLock.InsertionWindowMm(lockCem);

        // The HW.8 placeholder VALUE, handed in explicitly — too deep: the mouth is past the end of the lock's shank.
        // ⚖️ 2026-09-18 (HW.26): no longer "the groove is buried" — no ring is fitted, so the groove bounds nothing,
        // and the retired reason must not come back as the named one.
        string? strAt30 = AxialStack.Zone1InsertionConflict(new AnchorAxialStackCem { Zone1InsertionMm = 30f }, lockCem);
        Assert.NotNull(strAt30);
        Assert.Contains("zone1_insertion_mm", strAt30);
        Assert.Contains("past the end of the lock's", strAt30);
        Assert.DoesNotContain("DIN-471", strAt30);
        Assert.DoesNotContain("PEEK-contact zone", strAt30);
        Assert.Contains("HW.26 G1", strAt30);

        // Too shallow: the barbs stick out, and only that is named.
        string? strShallow = AxialStack.Zone1InsertionConflict(new AnchorAxialStackCem { Zone1InsertionMm = w.MinMm - 1f }, lockCem);
        Assert.NotNull(strShallow);
        Assert.Contains("PEEK-contact zone", strShallow);
        Assert.DoesNotContain("past the end of the lock's", strShallow);

        Assert.Null(AxialStack.Zone1InsertionConflict(
            new AnchorAxialStackCem { Zone1InsertionMm = (w.MinMm + w.MaxMm) / 2f }, lockCem));
    }

    // The shipped stack NAMES its Zone-1 lock instead of copying it, and the name must land on the right PART: a
    // solid shank of the Zone-1 shaft's own Ø — the Zone-3 lock has a channel, and its Ø is an HW.8 placeholder that
    // may yet become 11. A stack naming none gets no lock (never a default one), and a name resolving to another kind
    // refuses rather than parsing into record defaults — whose contact zone and shank length ARE the Zone-1 lock's.
    // MUTATION: drop the json key · point it at mechanical_lock.zone3.json · fall back to `new MechanicalLockCem()` ·
    // remove the kind check ⇒ each reds.
    [Fact]
    public void The_Shipped_Stack_Names_The_Solid_Lock_Of_Its_Own_Shaft__Never_A_Default_Or_Another_Kind()
    {
        string strStack = Path.Combine(CemFixtures.Dir(), "anchor_axial_stack.json");
        AnchorAxialStackCem cem = Cem.Parse<AnchorAxialStackCem>(File.ReadAllText(strStack));

        MechanicalLockCem? lockCem = AxialStack.Zone1Lock(cem, strStack);
        Assert.NotNull(lockCem);
        Assert.Equal(cem.Zone1.OuterDiameterMm, lockCem.ShankDiameterMm);
        Assert.Equal(0f, lockCem.BoreDiameterMm);

        Assert.Null(AxialStack.Zone1Lock(new AnchorAxialStackCem(), strStack));
        Assert.Throws<InvalidDataException>(() =>
            AxialStack.Zone1Lock(new AnchorAxialStackCem { Zone1LockManifest = "anchor_zone1.pine.json" }, strStack));
    }

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
