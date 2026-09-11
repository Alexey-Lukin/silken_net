// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
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
        AnchorCem cem = new() { OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, LengthMm = 12f };
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
        AnchorCem cem = new() { OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, LengthMm = 20f, GyroidPeriodRimMm = 1.3f, Topology = "stepped" };
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

    // The coating map of 01_02 §3.6 forbids ZnO-Ta, self-healing 8-HQ and biomimetic layers on the Zone-1
    // gyroid wall OUTRIGHT — a dielectric there blocks direct electron transfer, i.e. it does not degrade
    // the EBFC, it stops it. Until 2026-09-11 that rule had NO carrier on this part at all (00_07 HW.1):
    // AnchorCem had no Notes property, so a `notes` block written into a manifest would have been dropped
    // by the deserializer (unmapped members are ignored) and looked done. `draw anchor_zone1` still does
    // not exist, so nothing RENDERS these notes yet — this pin is what keeps them load-bearing meanwhile:
    // a new SKU cannot ship silent on the one restriction whose violation is unrecoverable.
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

    [Fact]
    public void Monolithic_Rod_Sets_The_Gyroid_Inner_Radius__Else_Legacy_Bore()
    {
        // 01_01 §1.4: with a solid bus rod the gyroid annulus starts at the rod surface (rod/2); without one
        // it falls back to the legacy hollow bore (bore/2). The solid rod core itself is voxConstruct-added in
        // BuildMonolithic — render-verified by `verify` (Voxels need Library.Go), not unit-tested here.
        Assert.Equal(0.5f, Zone1Anode.InnerRadiusMm(new AnchorCem { BusRodDiameterMm = 1.0f }));
        Assert.Equal(0.8f, Zone1Anode.InnerRadiusMm(new AnchorCem { BoreDiameterMm = 1.6f }));  // rod==0 ⇒ legacy bore
    }
}
