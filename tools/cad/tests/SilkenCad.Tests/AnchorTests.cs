// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using System.Text.Json;
using PicoGK;

namespace SilkenCad.Tests;

// Pure-logic golden tests — CEM parsing, gyroid SDF math, and generator selection. Fast and
// CI-friendly: no PicoGK Library.Go / display needed (only the managed SDF). The rendered-metric
// gates (porosity 65±, pore gradient, min-wall ≥ floor, manifold) run in the `verify`/`sweep`
// CLI on a PicoGK-capable runner. This is the .NET peer of `make -C firmware/test`.
public class AnchorTests
{
    [Fact]
    public void Cem_Parse_Reads_Kind_And_Defaults()
    {
        const string strJson = """{ "kind": "anchor_zone1", "name": "t", "gyroid_period_mm": 2.5 }""";
        Assert.Equal("anchor_zone1", Cem.Kind(strJson));

        AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
        Assert.Equal("t", cem.Name);
        Assert.Equal(2.5f, cem.GyroidPeriodMm);
        Assert.Equal(0f, cem.GyroidPeriodRimMm);   // absent ⇒ 0 ⇒ constant fallback
        Assert.Equal("sheet", cem.Topology);        // default topology
        Assert.Equal(0.1f, cem.VoxelSizeMm);        // default voxel
    }

    [Fact]
    public void Sheet_Gyroid_Is_Solid_On_The_Minimal_Surface()
    {
        // At the origin eq = 0, inside the wall band ⇒ negative SDF (solid).
        CartesianGyroid oGyroid = new(2.5f, 1.0f);
        Assert.True(oGyroid.fSignedDistance(Vector3.Zero) < 0f);
    }

    [Fact]
    public void Gyroid_Is_Periodic_In_One_Period()
    {
        CartesianGyroid oGyroid = new(2.5f, 1.0f);
        Vector3 vecPt = new(0.3f, 0.7f, 1.1f);
        float fHere = oGyroid.fSignedDistance(vecPt);
        float fShifted = oGyroid.fSignedDistance(vecPt + new Vector3(2.5f, 2.5f, 2.5f));
        Assert.Equal(fHere, fShifted, 3);
    }

    [Fact]
    public void Graded_Reduces_To_Core_Period_At_The_Core_Radius()
    {
        // At r = rCore the blend factor is 0 ⇒ the graded gyroid must equal the constant core gyroid.
        GradedCartesianGyroid oGraded = new(1f, 5f, 2.5f, 1.3f, 1.0f, 1.0f, bNetwork: false);
        CartesianGyroid oConst = new(2.5f, 1.0f);
        Vector3 vecPt = new(1f, 0f, 0.6f);   // |xy| = 1 = rCore
        Assert.Equal(oConst.fSignedDistance(vecPt), oGraded.fSignedDistance(vecPt), 3);
    }

    [Fact]
    public void Zoned_Uses_Core_Then_Rim_Period_Across_The_Boundary()
    {
        ZonedGyroid oZoned = new(3f, 2.5f, 1.3f, 1.0f);
        Vector3 vecCore = new(1f, 0f, 0.6f);   // r = 1 < 3 ⇒ core zone
        Vector3 vecRim = new(4f, 0f, 0.6f);    // r = 4 > 3 ⇒ rim zone
        Assert.Equal(new CartesianGyroid(2.5f, 1.0f).fSignedDistance(vecCore), oZoned.fSignedDistance(vecCore), 3);
        Assert.Equal(new CartesianGyroid(1.3f, 1.0f).fSignedDistance(vecRim), oZoned.fSignedDistance(vecRim), 3);
    }

    [Theory]
    [InlineData(2.5f, 0f, "sheet", typeof(CartesianGyroid))]          // no rim taper ⇒ constant v1
    [InlineData(2.5f, 2.0f, "sheet", typeof(GradedCartesianGyroid))]  // rim taper ⇒ continuous graded
    [InlineData(2.5f, 1.3f, "stepped", typeof(ZonedGyroid))]          // stepped topology ⇒ zoned
    // 🔴 The two network rows were MISSING while network was the minority branch; after ⚖️ 2026-09-10 it
    // is the branch every shipped anchor uses, so the factory dispatch for it was the one row this matrix
    // did not cover. Network takes the graded generator even with NO rim taper — `bGraded` ORs in
    // `bNetwork` (Zone1Anode.Gyroid), because CartesianGyroid only knows the |eq| band.
    [InlineData(2.5f, 0f, "network", typeof(GradedCartesianGyroid))]  // network ⇒ graded even w/o taper
    [InlineData(2.5f, 2.0f, "network", typeof(GradedCartesianGyroid))]
    public void Factory_Selects_The_Right_Generator(float fPeriod, float fRim, string strTopology, Type expected)
    {
        AnchorCem cem = new() { GyroidPeriodMm = fPeriod, GyroidPeriodRimMm = fRim, Topology = strTopology };
        Assert.IsType(expected, Zone1Anode.Gyroid(cem));
    }

    // --- ARCH.25 connectivity (pure-logic, no PicoGK Library.Go) — parity to the numeric experiment ---

    [Fact]
    public void Sheet_Gyroid_Is_Tricontinuous_Two_Open_Pore_Labyrinths()
    {
        // sheet (|eq| < 0.5w) splits the pore space into TWO disjoint labyrinths + one wall —
        // both open and percolating. 2 clusters is a topology FACT (HW.33), not a defect.
        Connectivity.Grid grid = Connectivity.SampleBox(new CartesianGyroid(2.5f, 1.0f), fExtentMm: 10f, fStepMm: 0.25f);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        Assert.Equal(2, m.PoreClusterCount);
        Assert.True(m.OpenPorosity > 0.98, $"open={m.OpenPorosity:F3}");
        Assert.True(m.ClosedPoreFraction < 0.02, $"closed={m.ClosedPoreFraction:F3}");
        Assert.True(m.PorePercolates is [true, true, true], $"perc=[{string.Join(",", m.PorePercolates)}]");
    }

    [Fact]
    public void Network_Gyroid_Is_Bicontinuous_One_Pore_One_Solid()
    {
        // network (single-sided eq) is bicontinuous: ONE pore + ONE solid network, both percolating.
        // Constant period+wall ⇒ the graded SDF reduces to a uniform network gyroid.
        GradedCartesianGyroid sdf = new(0f, 5f, 2.5f, 2.5f, 1.0f, 1.0f, bNetwork: true);
        Connectivity.Grid grid = Connectivity.SampleBox(sdf, fExtentMm: 10f, fStepMm: 0.25f);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        Assert.Equal(1, m.PoreClusterCount);
        Assert.True(m.OpenPorosity > 0.98, $"open={m.OpenPorosity:F3}");
        Assert.True(m.PorePercolates[2], "axial Z must percolate");
    }

    [Fact]
    public void Anchor_Envelope_Clips_Pore_Outside_The_Pipe()
    {
        // The bbox corner (r = outer·√2 > outer) is outside the pipe wall ⇒ Outside, never Pore;
        // and the rod's pore still percolates axially through the envelope.
        AnchorCem cem = new() { OuterDiameterMm = 11f, BusRodDiameterMm = 1.6f, LengthMm = 12f };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStepMm: 0.4f);

        Assert.Equal(Phase.Outside, grid.Cells[grid.Index(0, 0, grid.Nz / 2)]);
        ConnectivityMetrics m = Connectivity.Analyse(grid);
        Assert.True(m.OpenPorosity > 0.90, $"open={m.OpenPorosity:F3}");
        Assert.True(m.PorePercolates[2], "axial Z must percolate through the rod");
    }

    [Fact]
    public void Axial_Profile_Is_Flat_For_A_Radial_Gradient()
    {
        // The v2 gradient is RADIAL, so porosity along the axis (Z) must be ~uniform — the axial
        // golden test. A stepped SKU (radial zones) must still be axially flat.
        AnchorCem cem = new() { OuterDiameterMm = 11f, BusRodDiameterMm = 1.6f, LengthMm = 20f, GyroidPeriodRimMm = 1.3f, Topology = "stepped" };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStepMm: 0.4f);
        double[] aAxial = Connectivity.AxialProfile(grid);

        double dMin = aAxial.Min(), dMax = aAxial.Max();
        Assert.True(dMax - dMin < 0.10, $"axial porosity spread {dMax - dMin:F3} (min={dMin:F3} max={dMax:F3}) — should be ~flat");
    }

    // Enumerated, never a hand-written roster (CemFixtures says why) — a new SKU is pinned by existing.
    public static TheoryData<string> ShippedAnchorCems()
    {
        var data = new TheoryData<string>();
        foreach (string strFile in CemFixtures.AnchorFiles()) data.Add(strFile);
        return data;
    }

    // Each shipped manifest must resolve to its own topology's labyrinth count at the adaptive step:
    // a sheet gyroid is tricontinuous ⇒ 2, network is bicontinuous ⇒ 1, a `stepped` zoned gyroid is
    // genuinely single-labyrinth ⇒ 1. These are topology FACTS, not tuned thresholds.
    // 🔴 THIS TEST IS NO LONGER THE CARRIER OF THE period/24 RULE, and the loss was measured rather than
    // assumed. Until 2026-09-11 the shipped set was six SHEET SKUs, whose thin wall a coarse grid shreds
    // into false islands — welding the two labyrinths into one — so divisor 24 → 16 reddened exactly five
    // rows. Applying the network verdict emptied that: a network gyroid has ONE labyrinth by
    // construction, so under-resolution has nothing to weld, and the same mutation now leaves this
    // Theory FULLY GREEN (re-measured 2026-09-11 at /16). The rule is still true for a graded sheet wall;
    // what died is its carrier over the shipped set. Its carrier is now the sheet-derived case below —
    // do not delete that one as redundant with this one.
    [Theory]
    [MemberData(nameof(ShippedAnchorCems))]
    public void Shipped_Anchor_Cems_Converge_At_The_Adaptive_Step(string strFile)
    {
        AnchorCem cem = CemFixtures.Anchor(strFile);
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        int nExpected = cem.Topology == "sheet" ? 2 : 1;
        Assert.True(nExpected == m.PoreClusterCount,
            $"{strFile} ({cem.Topology}, rim period {CemFixtures.RimPeriodMm(cem):F1} mm) read {m.PoreClusterCount} pore " +
            $"cluster(s) at step {Connectivity.AdaptiveStepMm(cem):F4} mm, expected {nExpected}; " +
            $"solid-disconnected {m.SolidDisconnectedFraction:P3} — an under-resolved wall welds the labyrinths together");
    }

    // 🔴 THE carrier for Connectivity.AdaptiveStepMm's period/24 rule, and it exists because the shipped
    // set stopped exercising that rule on 2026-09-11 (see the Theory above). The rule is a property of a
    // graded SHEET wall — only there is the metal thin enough for a coarse grid to shred it into false
    // islands and weld the two labyrinths into one — so its carrier must BE a graded sheet. It takes the
    // real pine geometry and overrides only the topology, because a synthetic toy coupon proves the
    // algorithm compiles, never that it survives real geometry at true scale (that is how both tortuosity
    // bugs got through a green suite).
    // MUTATION: Connectivity.AdaptiveStepMm divisor 24 → 16 ⇒ this test must red with 1 cluster.
    [Fact]
    public void A_Graded_Sheet_Wall_Still_Needs_The_Period_24_Step()
    {
        AnchorCem cem = CemFixtures.Anchor("anchor_zone1.pine.json") with { Topology = "sheet", GyroidWallParam = 1.0f };
        Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem);
        ConnectivityMetrics m = Connectivity.Analyse(grid);

        Assert.True(m.PoreClusterCount == 2,
            $"a graded SHEET gyroid read {m.PoreClusterCount} pore cluster(s) at step " +
            $"{Connectivity.AdaptiveStepMm(cem):F4} mm (solid-disconnected {m.SolidDisconnectedFraction:P3}) — " +
            "a coarser step shreds the thin wall into false islands and welds the two labyrinths into one");
    }

    // 🔴 The carrier that makes the `Topology` RECORD DEFAULT non-load-bearing. It is NOT the pin that
    // `cem_canon_sync.rb` declares refused (⚖️ 2026-09-09): that one would assert each C# default EQUALS
    // its canon value — a different subject, and refused because all such defaults are correct today, so
    // its true set is empty. This one asserts the shipped manifests do not RELY on the default at all,
    // which is what the 2026-09-10 network verdict made necessary: an omitted key used to mean `sheet`,
    // i.e. a new SKU would silently inherit the branch a founder verdict rejected, and a factory STL cut
    // from it would go out on that branch. A parsed AnchorCem cannot tell an absent key from an explicit
    // "sheet", so this reads the RAW json — a pin on the parsed record would be vacuous by construction.
    // MUTATION: delete the "topology" line from any cem/anchor_zone1.*.json ⇒ this test must red naming
    // that file.
    [Fact]
    public void Every_Shipped_Anchor_Cem_Declares_Its_Topology()
    {
        string[] aSilent = [.. CemFixtures.AnchorFiles()
            .Where(f => !File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)).Contains("\"topology\""))];

        Assert.True(aSilent.Length == 0,
            $"{string.Join(", ", aSilent)} do not declare `topology` and would inherit the Cem.cs default " +
            "(`sheet`) — the branch ⚖️ founder 2026-09-10 rejected for the anode (00_07 HW.33). " +
            "Declare it explicitly; the default exists for synthetic in-test coupons only.");
    }

    // The core of every shipped anchor is the monolithic bus rod (01_01 §1.4), and AnchorCem has NO bore
    // slot: `Cem.Parse` ignores unmapped members, so a `bore_diameter_mm` key written back into a manifest
    // would parse cleanly and shape nothing — a number on the SSOT surface that the part does not carry.
    // And a manifest that omits the rod does not fail to build: Zone1Anode.InnerRadiusMm reads 0 and the
    // lattice reaches the axis, i.e. a factory STL with no conductor. Both are invisible after parsing, so
    // this reads the RAW json, like the topology pin above.
    // MUTATION: add `"bore_diameter_mm": 1.6,` to any cem/anchor_zone1.*.json · delete its
    // "bus_rod_diameter_mm" line ⇒ each reds naming that file.
    [Fact]
    public void Every_Shipped_Anchor_Cem_Declares_Its_Bus_Rod_And_No_Bore()
    {
        string[] aNoRod = [.. CemFixtures.AnchorFiles()
            .Where(f => !File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)).Contains("\"bus_rod_diameter_mm\""))];
        string[] aBore = [.. CemFixtures.AnchorFiles()
            .Where(f => File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)).Contains("\"bore_diameter_mm\""))];

        Assert.True(aNoRod.Length == 0,
            $"{string.Join(", ", aNoRod)} declare no `bus_rod_diameter_mm` — the lattice would reach the axis, and " +
            "F3 would have no rod to check the cathode channel against (01_01 §1.4; whether the rod runs through " +
            "the anode is the render model of an open branch, 00_07 HW.34).");
        Assert.True(aBore.Length == 0,
            $"{string.Join(", ", aBore)} carry `bore_diameter_mm`, which AnchorCem has no slot for — the key " +
            "evaporates on parse; the rod is the core.");
    }

    // The coating map of 01_02 §3.6 forbids ZnO-Ta, self-healing 8-HQ and biomimetic layers on the Zone-1
    // gyroid wall OUTRIGHT — a dielectric there blocks direct electron transfer, i.e. it does not degrade
    // the EBFC, it stops it. Until 2026-09-11 that rule had NO carrier on this part at all (00_07 HW.1):
    // AnchorCem had no Notes property, so a `notes` block written into a manifest would have been dropped
    // by the deserializer (unmapped members are ignored) and looked done. `draw anchor_zone1` RENDERS them
    // since 2026-09-11, so the pin is no longer the only thing keeping them load-bearing — it is now the
    // thing keeping a NEW SKU from shipping silent on the one restriction whose violation is unrecoverable.
    // ⛔ Declared ceiling: PRESENCE of the field, never its correctness — no gate can read a coating rule.
    // MUTATION: drop the "coating_restriction" key from any cem/anchor_zone1.*.json ⇒ reds naming it.
    // 🔴 Both halves are load-bearing and they fail DIFFERENTLY — adversarial review caught the first
    // version of this test carrying only the raw-text half, which cannot see the defect it was written
    // for: delete `AnchorCem.Notes` and the KEY stays in every json while the block evaporates on parse,
    // i.e. green while the mine is re-armed. Raw text catches a manifest that never declared it; the
    // PARSE catches a record that cannot hold it.
    [Fact]
    public void Every_Shipped_Anchor_Cem_Declares_Its_Coating_Restriction()
    {
        string[] aSilentInJson = [.. CemFixtures.AnchorFiles()
            .Where(f => !File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)).Contains("\"coating_restriction\""))];

        Assert.True(aSilentInJson.Length == 0,
            $"{string.Join(", ", aSilentInJson)} declare no `coating_restriction` — the Zone-1 gyroid wall is " +
            "the one surface where a dielectric coating does not degrade the cell but stops it (01_02 §3.6). " +
            "A manifest silent on that rule hands the shop nothing to refuse.");

        string[] aLostOnParse = [.. CemFixtures.AnchorFiles()
            .Where(f => string.IsNullOrWhiteSpace(
                Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), f))).Notes?.CoatingRestriction))];

        Assert.True(aLostOnParse.Length == 0,
            $"{string.Join(", ", aLostOnParse)} carry the key in the file but it does NOT survive parsing — " +
            "`AnchorCem` has no slot for it, and `Cem.Parse` drops unmapped members in silence. That is the " +
            "exact state this part was in until 2026-09-11 (00_07 HW.1): done-looking and inert.");
    }

    // 🔴 The SAME pin one field over, and the reason it exists is that the first one did not generalise:
    // `AnchorCem` had no `Tolerances` slot either, so the very next block written into these manifests
    // would have evaporated exactly like `notes` did — one day after that fix landed (00_07 HW.1). Two
    // holes in one record, and the pass that closed the first saw only what it was hunting.
    // ⛔ Declared ceiling: PRESENCE of the block, never the correctness of a limit. The envelope Ø
    // deliberately carries NO limits — canon 01_01 §4.2 wants Lamé-window micrometres and that window is
    // unsolved (00_07 HW.3) — so a NAMED feature with blank sides is the intended state: the shop reads
    // `NOT SPECIFIED IN CEM` and asks, instead of reading a default into a missing line.
    // MUTATION (both halves verified 2026-09-11): drop the "tolerances" block from any
    // cem/anchor_zone1.*.json ⇒ reds naming it; leave the block but empty (`"tolerances": {}`) ⇒ reds on
    // the parse half while the key is still in the file. ⚠️ The obvious third mutation — deleting
    // `AnchorCem.Tolerances` — does NOT red this test, it fails to COMPILE, because `Drawing.AnchorZone1`
    // now reads the property. That is a stronger guard than a pin and it is also why the parse half here
    // guards a DIFFERENT case than its `coating_restriction` sibling: there the slot could vanish while
    // every manifest kept its key, here it cannot.
    [Fact]
    public void Every_Shipped_Anchor_Cem_Declares_A_Tolerance_Block_For_Its_Envelope()
    {
        string[] aSilentInJson = [.. CemFixtures.AnchorFiles()
            .Where(f => !File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)).Contains("\"tolerances\""))];

        Assert.True(aSilentInJson.Length == 0,
            $"{string.Join(", ", aSilentInJson)} declare no `tolerances` block — the drawing then prints NO " +
            "TOLERANCES section at all, which is the SILENT half of the loud-absence rule: the shop cannot " +
            "tell an undeclared dimension from an unasked question (01_02 §6).");

        string[] aLostOnParse = [.. CemFixtures.AnchorFiles()
            .Where(f => Cem.Parse<AnchorCem>(File.ReadAllText(Path.Combine(CemFixtures.Dir(), f)))
                           .Tolerances?.Features is not { Count: > 0 })];

        Assert.True(aLostOnParse.Length == 0,
            $"{string.Join(", ", aLostOnParse)} carry the key in the file but no named feature survives " +
            "parsing — either `AnchorCem` lost its slot or the block names nothing, and both render as an " +
            "absent section rather than an open question.");
    }

    // 🔴 THE printed part carries NO core, and the manifest's own rod field must not put one back.
    // ⚖️ founder 2026-09-18 (00_07 HW.1): the welded branch prints the anode WITHOUT a bus rod and welds a
    // drawn wire to its top face, so `bus_rod_diameter_mm` describes an ASSEMBLY part — the wire — and a
    // reader that turns it into a printed core would hand the factory the branch the founder removed.
    // MUTATION: make InnerRadiusMm return `cem.BusRodDiameterMm / 2f` again ⇒ this reds naming the radius.
    [Fact]
    public void The_Printed_Part_Carries_No_Core()
    {
        AnchorCem[] aShipped = [.. CemFixtures.AnchorFiles().Select(CemFixtures.Anchor)];
        Assert.Contains(aShipped, c => c.BusRodDiameterMm > 0f);   // counter-lamp: the wire IS declared…
        foreach (AnchorCem cem in aShipped)                        // …and none of it reaches the printed body
            Assert.Equal(0f, Zone1Anode.InnerRadiusMm(cem));
        Assert.Equal(0f, Zone1Anode.InnerRadiusMm(new AnchorCem { BusRodDiameterMm = 1.0f }));
    }

    // 🔴 A NOTE puts the core back too — and on the factory sheet, where the pin above cannot see it
    // (00_07 HW.1). Every shipped anchor note said the model draws the rod «as a solid core through the
    // annulus» and called that simplification OPEN; the welded branch closed it the other way, and the
    // sentence went on printing on the published anchor sheet beside the sheet's own «NO central bore»
    // (skill ssot-maintenance guard-craft #176: an artefact that names the condition of its own falsity
    // outlives the condition firing, because nothing reads the condition). So the notes are tied to the
    // fact the pin above reads: while the printed part has no core, no note of a shipped anchor describes
    // one. When a verdict brings a core back this reds FIRST — rewrite the notes with the geometry.
    // ⛔ Declared ceiling: the tokens are the two spellings the stale note used; the same claim in other
    // words passes, and a note is judged only for what it says about a CORE, nothing else.
    // MUTATION: put «annulus» back into any shipped anchor note ⇒ this reds naming the file and the field.
    [Fact]
    public void While_The_Part_Has_No_Core_No_Shipped_Note_Describes_One()
    {
        string[] aTokens = ["annulus", "solid core"];
        var aHits = new List<string>();
        foreach (string f in CemFixtures.AnchorFiles())
        {
            string strJson = File.ReadAllText(Path.Combine(CemFixtures.Dir(), f));
            if (Zone1Anode.InnerRadiusMm(Cem.Parse<AnchorCem>(strJson)) > 0f) continue;   // a cored part may say so
            using JsonDocument doc = JsonDocument.Parse(strJson);
            if (!doc.RootElement.TryGetProperty("notes", out JsonElement notes)) continue;
            foreach (JsonProperty field in notes.EnumerateObject())
            {
                IEnumerable<string> aText = field.Value.ValueKind switch
                {
                    JsonValueKind.String => [field.Value.GetString()!],
                    JsonValueKind.Array => field.Value.EnumerateArray()
                        .Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!),
                    _ => [],
                };
                foreach (string s in aText)
                    foreach (string tok in aTokens.Where(t => s.Contains(t, StringComparison.OrdinalIgnoreCase)))
                        aHits.Add($"{f} notes.{field.Name}: «{tok}»");
            }
        }
        Assert.True(aHits.Count == 0,
            "a shipped anchor note describes a core the printed part does not have (Zone1Anode.InnerRadiusMm = 0; " +
            $"the bus wire is WELDED on, 01_01 §3 step 1b) — the sheet would print it: {string.Join(" · ", aHits)}");
    }

    // 🔴 The convergence LADDER is a committed measurement, and its cache can go stale in a way nothing
    // else here would notice: the ladder's own floor lives in `Connectivity.AdaptiveStepMm`, so lowering
    // the clamp (or changing the /24 divisor) silently turns every committed rung into a statement about
    // a grid the sampler no longer uses — while the JSON stays internally perfect. This pin recomputes
    // the shipped step from the code and compares it to what each cache says it measured.
    // ⛔ Declared ceiling: it judges the cache's PROVENANCE, never its topology numbers — those come from
    // a run, and re-running the ladder inside the suite would add ~20 s to a 14 s suite for a probe.
    // MUTATION: change the 0.06f floor or the 24f divisor in Connectivity.AdaptiveStepMm ⇒ this reds
    // naming every SKU whose ladder must be re-run (00_07 HW.51).
    [Fact]
    public void Every_Committed_Convergence_Ladder_Was_Measured_On_Todays_Sampler()
    {
        string dir = Path.Combine(Directory.GetParent(CemFixtures.Dir())!.FullName, "cache", "topology");
        Assert.True(Directory.Exists(dir), $"no convergence ladders committed at {dir} — the claim in " +
                                           "Connectivity.cs and 01_02 §1.3 would have no measurer (00_07 HW.51)");
        var aStale = new List<string>();
        foreach (AnchorCem cem in CemFixtures.AnchorFiles().Select(CemFixtures.Anchor))
        {
            string path = Path.Combine(dir, $"convergence.{cem.Name}.json");
            if (!File.Exists(path)) { aStale.Add($"{cem.Name}: no ladder"); continue; }
            using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(path));
            double dSaid = doc.RootElement.GetProperty("shipped_adaptive_step_mm").GetDouble();
            double dNow = Connectivity.AdaptiveStepMm(cem);
            if (Math.Abs(dSaid - dNow) > 1e-6)
                aStale.Add($"{cem.Name}: ladder measured at {dSaid:F4} mm, sampler now says {dNow:F4} mm");
        }
        Assert.True(aStale.Count == 0,
            "the committed convergence ladders no longer describe the shipped sampler — re-run " +
            $"`converge <cem> --divisors 24,32`: {string.Join(" · ", aStale)}");
    }

    // 🔴 ONE part, ONE inner envelope (00_07 HW.33). A reader that samples from any radius other than the one
    // `build` cuts drops — or invents — a ring the printed part carries, silently, because the ring is small.
    // Measured 2026-09-13 with a 0.3 mm ring on the shipped seven: `stepped`'s sub-floor share moved −0.79 pp
    // (past its golden tolerance) and every network SKU's under 0.04 pp (inside it), so the golden gate alone
    // would see such a defect on one SKU of seven. The pin above holds the SOURCE; this one holds its READERS.
    // Covered: Connectivity.SampleAnchor (and through it CheckPrintFidelity and WallScan, which sample only
    // via it) · Validation's per-shell radii · VoxelFea.SampleAnchorAsBuilt. Each reader is judged against
    // the radius Zone1Anode.Envelope cuts, never against another reader, so two readers wrong the same way
    // still red.
    // ⛔ Declared ceiling: MeasureAnchor's shell loop needs voxels, so what is pinned is its pure seam
    // (ShellBoundariesMm), not the loop itself; a reader that grows its own sampler is outside this pin.
    // 🔴 SECOND declared ceiling, since 2026-09-18: the cut radius is now 0 for every shipped part (the
    // welded branch — the anode has no printed core), so the NUMERIC half of this pin compares zeros. It
    // still reds on a reader that invents a nonzero radius, and nothing else. The half that stayed alive
    // is the SOURCE half below: each reader must take the radius from the one home rather than compute it,
    // which is the divergence the numeric half used to catch on its own.
    // MUTATION (2026-09-13, each alone): cut at r = 0 — ignore the rod — in Connectivity.SampleAnchor ·
    // in Validation.ShellBoundariesMm · in VoxelFea.SampleAnchorAsBuilt ⇒ each reds naming its own reader.
    // MUTATION (2026-09-18, source half): replace `Zone1Anode.InnerRadiusMm(cem)` with a literal in any of
    // the three readers ⇒ this reds naming that file.
    [Fact]
    public void Every_Anchor_Reader_Samples_The_Inner_Radius_Build_Cuts()
    {
        const float fStep = 0.05f;
        // The SOURCE half: every reader takes the radius from the one home. Checked as text because the
        // numeric half can no longer discriminate — the cut is 0 on every shipped part since the welded
        // branch, so a reader that hardcoded 0 would agree with the home by accident.
        string src = Path.Combine(Directory.GetParent(CemFixtures.Dir())!.FullName, "src", "SilkenCad");
        foreach (string strReader in new[] { "Connectivity.cs", "VoxelFea.cs", "Validation.cs" })
        {
            string strCode = File.ReadAllText(Path.Combine(src, strReader));
            Assert.True(strCode.Contains("Zone1Anode.InnerRadiusMm("),
                $"{strReader} no longer reads the inner radius from its one home (Zone1Anode.InnerRadiusMm) — " +
                "a second formula for one radius is how the drawing, the FE and the part diverge (00_07 HW.33)");
        }

        // A ten-cell slab of each real manifest: the radius does not depend on length, the runtime does.
        AnchorCem[] aRodBearing = [.. CemFixtures.AnchorFiles()
            .Select(CemFixtures.Anchor)
            .Where(c => c.BusRodDiameterMm > 0f)
            .Select(c => c with { LengthMm = 10 * fStep })];
        Assert.NotEmpty(aRodBearing);   // counter-lamp: the wire is still declared by the shipped manifests

        foreach (AnchorCem cem in aRodBearing)
        {
            float fCut = Zone1Anode.InnerRadiusMm(cem);
            AssertInnerBoundary("Connectivity.SampleAnchor",
                Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fStep), cem, fCut);
            AssertInnerBoundary("VoxelFea.SampleAnchorAsBuilt",
                VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Gyroid(cem), cem, fStep), cem, fCut);

            float fShellInner = Validation.ShellBoundariesMm(cem, 5)[0];
            Assert.True(MathF.Abs(fShellInner - fCut) < 1e-6f,
                $"{cem.Name}: Validation's per-shell porosity starts at r = {fShellInner:F3} mm while " +
                $"Zone1Anode.Envelope cuts r = {fCut:F3} mm — the shells no longer sum back to the part's porosity");
        }
    }

    // Reads the inner boundary a sampled grid actually carries off its own cells: the cut radius must lie
    // between the widest Outside centre near the axis (the hole) and the narrowest centre that is inside.
    // Centres follow the anchor samplers' shared origin, (−R, −R) + (i + ½)·step.
    private static void AssertInnerBoundary(string strReader, Connectivity.Grid grid, AnchorCem cem, float fCut)
    {
        double dR = cem.OuterDiameterMm / 2.0, dHoleMax = double.NegativeInfinity, dInsideMin = double.PositiveInfinity;
        for (int i = 0; i < grid.Nx; i++)
            for (int j = 0; j < grid.Ny; j++)
            {
                double x = -dR + ((i + 0.5) * grid.StepMm), y = -dR + ((j + 0.5) * grid.StepMm);
                double r = Math.Sqrt((x * x) + (y * y));
                if (r > dR / 2) continue;   // past the rim the corners are Outside too; only the hole is asked about
                if (grid.Cells[grid.Index(i, j, 0)] == Phase.Outside) dHoleMax = Math.Max(dHoleMax, r);
                else dInsideMin = Math.Min(dInsideMin, r);
            }

        Assert.True(dHoleMax < fCut && fCut <= dInsideMin,
            $"{cem.Name}: {strReader} samples an inner boundary between r = {dHoleMax:F3} and {dInsideMin:F3} mm, " +
            $"but Zone1Anode.Envelope cuts r = {fCut:F3} mm (the rod surface) — " +
            "the ring between them is in the printed part and misread by every metric taken off this grid");
    }
}
