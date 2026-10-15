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
        Assert.Null(cem.Zone1ShankLengthMm);                    // resolved at load from the lock — never parsed (⚖️ G1 2026-10-12)
        Assert.Null(Cem.Parse<AnchorAxialStackCem>(
            """{ "kind": "anchor_axial_stack", "name": "x", "zone1_shank_length_mm": 30, "zone1_insertion_mm": 30 }""").Zone1ShankLengthMm);
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
        // F2: bore 50 − (the Zone-1 lock's whole shank 18 + Zone-3 shank 14) = 18 mm of PEEK gap between the two shank
        // ends (⚖️ G1 2026-10-12; 6 mm on the retired placeholder insertion 30).
        AnchorAxialStackCem cem = R(new());
        Assert.Equal(18f, AxialStack.InsertionBudgetMm(cem), 3);
        Assert.True(AxialStack.InsertionBudgetMm(cem) >= 0, "the two shanks must not collide inside the sleeve bore");
    }

    [Fact]
    public void Z_Layout_Stacks_From_The_Tree_Side_Up()
    {
        // Datum: anode bottom z=0. The anode is the gyroid body (40) + the lock's shank (18), top face at 58; the shank
        // inserts whole (⚖️ G1 2026-10-12), so the sleeve bottom sits on the gyroid-to-shank junction at 40 and the whole gyroid is below
        // it, in the wood; sleeve top = 90; capsule lifts so the flange shank (14) inserts ⇒ lift = 90 − 14 = 76; overall
        // stack length = 90 + flange thickness 3 = 93. The embedded depth is 90, not 93: the flange seats on the bark, so
        // its UNDERSIDE is the bark line (⚖️ HW.33 2026-09-18). (Until G1: 10 · 60 · 46 · 63 — 30 mm of the 40 mm envelope in the bore.)
        AnchorAxialStackCem cem = R(new());
        Assert.Equal(58f, AxialStack.Zone1TopZMm(cem), 3);
        Assert.Equal(40f, AxialStack.SleeveBottomZMm(cem), 3);
        Assert.Equal(cem.Zone1.LengthMm, AxialStack.SleeveBottomZMm(cem), 3);   // no lattice inside the sleeve
        Assert.Equal(90f, AxialStack.SleeveTopZMm(cem), 3);
        Assert.Equal(76f, AxialStack.CapsuleLiftZMm(cem), 3);
        Assert.Equal(93f, AxialStack.OverallStackLengthMm(cem), 3);
        Assert.Equal(58f, AxialStack.BusWireBottomZMm(cem), 3);   // welded on the shank's top face
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
        Assert.Equal(75f, AxialStack.LinerBottomZMm(cem), 3);   // shank face 76 − 1.0 protrusion
        Assert.Equal(93f, AxialStack.LinerTopZMm(cem), 3);      // flush with the pogo face
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
        => R(new()
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
        });

    // ── Zone-1 insertion = the lock's whole shank (⚖️ 00_07 HW.26 G1, 2026-10-12, branch (А)) ──

    // The shank's one home is the lock manifest, and the stack takes it at load; the insertion is that shank, on the
    // deep edge of the window the lock admits. MUTATION: type a number into Zone1InsertionMm · read the shank from the
    // record default instead of the lock · drop the Load refusal ⇒ a row reds.
    [Fact]
    public void The_Shank_Inserts_Whole__Its_Length_Comes_From_The_Lock_And_Sits_On_The_Window_Deep_Edge()
    {
        string strStack = Path.Combine(CemFixtures.Dir(), "anchor_axial_stack.json");
        AnchorAxialStackCem cem = AxialStack.Load(strStack);
        MechanicalLockCem lockCem = Lock();
        MechanicalLock.InsertionWindow w = MechanicalLock.InsertionWindowMm(lockCem);
        Assert.Equal(lockCem.ShankLengthMm, cem.Zone1ShankLengthMm);
        Assert.Equal(lockCem.ShankLengthMm, AxialStack.Zone1InsertionMm(cem), 3);
        Assert.Equal(w.MaxMm, AxialStack.Zone1InsertionMm(cem), 3);
        Assert.True(AxialStack.Zone1InsertionMm(cem) >= w.MinMm, "the barbs must be inside the sleeve");
        // A lock with a longer shank moves the insertion and the sleeve with it — nothing typed in the stack.
        AnchorAxialStackCem longer = cem with { Zone1ShankLengthMm = lockCem.ShankLengthMm + 4f };
        Assert.Equal(AxialStack.SleeveBottomZMm(cem), AxialStack.SleeveBottomZMm(longer), 3);   // still on the junction
        Assert.Equal(AxialStack.InsertionBudgetMm(cem) - 4f, AxialStack.InsertionBudgetMm(longer), 3);
    }

    // Loud absence: a stack that was never resolved against its lock cannot be laid out, and one that names no lock
    // cannot be loaded — never a default shank.
    [Fact]
    public void An_Unresolved_Stack_Throws__A_Stack_Naming_No_Lock_Is_Refused_At_Load()
    {
        Assert.Throws<InvalidOperationException>(() => AxialStack.SleeveBottomZMm(new AnchorAxialStackCem()));
        string strTmp = Path.Combine(Path.GetTempPath(), $"stack_no_lock_{Guid.NewGuid():N}.json");
        File.WriteAllText(strTmp, """{ "kind": "anchor_axial_stack", "name": "x" }""");
        try { Assert.Throws<InvalidDataException>(() => AxialStack.Load(strTmp)); }
        finally { File.Delete(strTmp); }
    }

    private static MechanicalLockCem Lock()
        => Cem.Parse<MechanicalLockCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), "mechanical_lock.zone1.json")));

    // A stack resolved against the shipped Zone-1 lock, as AxialStack.Load does for a manifest on disk.
    private static AnchorAxialStackCem R(AnchorAxialStackCem cem) => cem with { Zone1ShankLengthMm = Lock().ShankLengthMm };

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

    // ── `build --parts` (2026-10-15): the stack as separate bodies in the stack frame (z = 0 at the anode bottom) ──
    // The rows ARE what the CLI writes and measures each written mesh against (Program.ExportParts), so these pins hold
    // the files' names and places. MUTATION: drop the capsule lift from the halves · lift the radome by the capsule lift
    // alone · rename a body · build the liner under the wire's condition ⇒ a row reds.
    [Fact]
    public void Build_Parts_Writes_Every_Body_The_Shipped_Stack_Holds_Each_In_The_Stack_Frame()
    {
        AnchorAxialStackCem cem = AxialStack.Load(Path.Combine(CemFixtures.Dir(), "anchor_axial_stack.json"));
        IReadOnlyList<AssemblyPart<AxialStackVoxels>> aParts = AxialStack.Parts(cem);
        Assert.Equal(["zone1", "zone2_sleeve", "flange", "radome", "bus_wire", "liner"], aParts.Select(p => p.Name));

        // The layout Z_Layout_Stacks_From_The_Tree_Side_Up pins (58 · 40/90 · 76 · 93), now body by body.
        AssertSpan(aParts, "zone1", 0f, 58f);          // gyroid body 40 + lock shank 18 — as ONE solid envelope
        AssertSpan(aParts, "zone2_sleeve", 40f, 90f);  // mouth on the gyroid-to-shank junction
        AssertSpan(aParts, "flange", 76f, 93f);        // shank end 90 − 14 → pogo face
        AssertSpan(aParts, "radome", 88f, 106f);       // rim on the bayonet datum (76 + 12) → crown (+18)
        AssertSpan(aParts, "bus_wire", 58f, 93f);      // weld seam on the anode top → pogo face
        AssertSpan(aParts, "liner", 75f, 93f);         // 1.0 below the shank face → pogo face

        // The capsule halves are the capsule's OWN rows, carried up by the lift Build gives the merged capsule.
        float fLift = AxialStack.CapsuleLiftZMm(cem);
        foreach (AssemblyPart<AssemblyVoxels> p in Assembly.Parts(cem.Capsule))
            AssertSpan(aParts, p.Name, p.ZBottomMm + fLift, p.ZTopMm + fLift);

        // Inside the stack: nothing below the anode bottom (the datum), nothing above the radome crown (its top).
        float fTop = aParts.Single(p => p.Name == "radome").ZTopMm;
        Assert.All(aParts, p => Assert.InRange(p.ZBottomMm, 0f, p.ZTopMm));
        Assert.All(aParts, p => Assert.True(p.ZTopMm <= fTop, $"{p.Name} rises above the crown"));

        // ⛔ The overlap the view shows on purpose: the collar is not modelled, so the radome rim sits the bayonet-Z
        //    deficit below the flange face (and the Zone-3 shank floats in the bore — F1, pinned above).
        Assert.Equal(Assembly.BayonetZMismatchMm(cem.Capsule),
                     aParts.Single(p => p.Name == "flange").ZTopMm - aParts.Single(p => p.Name == "radome").ZBottomMm, 3);
    }

    // A body the stack does not hold gets no file — never an empty or default one. The predicates are the ones Build reads.
    [Fact]
    public void Build_Parts_Writes_No_Wire_Or_Liner_The_Stack_Does_Not_Hold()
    {
        string[] aNoRod = [.. AxialStack.Parts(R(new())).Select(p => p.Name)];
        Assert.DoesNotContain("bus_wire", aNoRod);
        Assert.DoesNotContain("liner", aNoRod);

        string[] aNoLiner = [.. AxialStack.Parts(Fix(linerMm: 0f)).Select(p => p.Name)];
        Assert.Contains("bus_wire", aNoLiner);
        Assert.DoesNotContain("liner", aNoLiner);
    }

    private static void AssertSpan(IReadOnlyList<AssemblyPart<AxialStackVoxels>> aParts, string strName, float fBottom, float fTop)
    {
        AssemblyPart<AxialStackVoxels> p = aParts.Single(x => x.Name == strName);
        Assert.Equal(fBottom, p.ZBottomMm, 3);
        Assert.Equal(fTop, p.ZTopMm, 3);
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
