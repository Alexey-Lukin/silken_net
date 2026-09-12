// SPDX-License-Identifier: AGPL-3.0-or-later
namespace SilkenCad;

// Resolution adequacy: is every declared feature actually REPRESENTABLE on the voxel grid the
// manifest asks for? (00_07 HW.51, born from the HW.34 liner.)
//
// 🔴 The incident this exists for, in full, because the shape is what generalises. The bus liner is a
// 0.15 mm wall; the assembly renders at voxel 0.2 mm. Rendered on its own it measured 9.99 mm³
// against 9.75 mm³ analytic — a healthy body — and merged into the stack it added exactly 0.00 mm³,
// because at that voxel the Ø1.0 rod and the Ø1.35 channel ARE the same voxels and the annulus
// between them has nowhere to land. Nothing was wrong with the geometry, the manifest or the merge;
// the GRID could not hold the feature. That is invisible to every gate we had, because each one asks
// whether the render matches the model and the model was never in the grid to begin with.
//
// 🔑 Three design choices, each bought by a measured trap:
//   • Walk the PARSED RECORD TREE, never the JSON. `anchor_axial_stack.json` declares three numbers
//     and carries about thirty: everything else is a `Cem.cs` record default written for a part voxel
//     of 0.05–0.1 and then inherited at the assembly voxel of 0.2. A key-walking check sees none of them.
//   • Carry DERIVED features, not only declared ones. The two features that actually bite are both
//     derived — the rod↔channel annulus `(bore − rod)/2` and the lattice's own metal thickness
//     (§5.5) — and no field holds either.
//   • Two thresholds, not one. At 2 voxels a feature EXISTS in the grid; at 4 its VOLUME is worth
//     quoting. Reporting one number would force a choice between "it vanished" and "it is coarse",
//     which are different findings with different costs.
//
// ⚠️ DECLARED CEILING. This is arithmetic on nominal dimensions — it cannot see whether a feature
// survives a Boolean, whether an inclined surface staircases badly, or whether the SDF is sampled at
// its centre or its corner. It answers exactly one question: could the grid hold this size at all.
internal static class Resolution
{
    /// <summary>Below this the feature can be absent from the grid entirely.</summary>
    internal const double RepresentedVoxels = 2.0;

    /// <summary>Below this the feature is present but its measured volume is not worth quoting.</summary>
    internal const double HonestVolumeVoxels = 4.0;

    internal readonly record struct Feature(string Path, double ValueMm, double VoxelMm, bool Derived)
    {
        public double Voxels => VoxelMm > 0.0 ? ValueMm / VoxelMm : double.PositiveInfinity;
        public bool Represented => Voxels >= RepresentedVoxels;
        public bool VolumeHonest => Voxels >= HonestVolumeVoxels;
        public override string ToString()
            => $"{Path} = {ValueMm:F3} mm at voxel {VoxelMm:F2} mm ⇒ {Voxels:F2} voxels{(Derived ? " (derived)" : "")}";
    }

    // A zero is the corpus's "absent" sentinel on several of these fields (no rod, no liner, solid
    // shank, no rim taper), never a zero-thickness feature — so it is skipped rather than failed.
    private static void Add(List<Feature> a, string strPath, double dValueMm, double dVoxelMm, bool bDerived = false)
    {
        if (dValueMm > 0.0) a.Add(new Feature(strPath, dValueMm, dVoxelMm, bDerived));
    }

    internal static IReadOnlyList<Feature> Features(AnchorCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        // The lattice's own metal is the thinnest thing in this part and no field declares it.
        Add(a, strPrefix + "lattice_thickness", TopologyCrossChecks.LatticeThicknessMm(cem), dVoxelMm, bDerived: true);
        // The legacy hollow bore is NOT a feature when a monolithic rod is declared — the rod fills it
        // (Zone1Anode.InnerRadiusMm), so measuring the annulus there would invent a gap the part lacks.
        if (cem.BusRodDiameterMm <= 0f)
            Add(a, strPrefix + "bore_diameter_mm", cem.BoreDiameterMm, dVoxelMm);
        else
            Add(a, strPrefix + "bus_rod_diameter_mm", cem.BusRodDiameterMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(CathodeFlangeCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        Add(a, strPrefix + "bus_liner_thickness_mm", cem.BusLinerThicknessMm, dVoxelMm);
        Add(a, strPrefix + "barb_height_mm", cem.BarbHeightMm, dVoxelMm);
        Add(a, strPrefix + "groove_depth_mm", cem.GrooveDepthMm, dVoxelMm);
        Add(a, strPrefix + "groove_width_mm", cem.GrooveWidthMm, dVoxelMm);
        Add(a, strPrefix + "o_ring_groove_depth_mm", cem.ORingGrooveDepthMm, dVoxelMm);
        Add(a, strPrefix + "o_ring_groove_width_mm", cem.ORingGrooveWidthMm, dVoxelMm);
        Add(a, strPrefix + "isolation_ring_width_mm", cem.IsolationRingWidthMm, dVoxelMm);
        Add(a, strPrefix + "lug_radius_mm", cem.LugRadiusMm, dVoxelMm);
        Add(a, strPrefix + "lug_protrusion_mm", cem.LugProtrusionMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(RadomeCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        Add(a, strPrefix + "wall_thickness_mm", cem.WallThicknessMm, dVoxelMm);
        Add(a, strPrefix + "slot_clearance_mm", cem.SlotClearanceMm, dVoxelMm);
        Add(a, strPrefix + "o_ring_groove_depth_mm", cem.ORingGrooveDepthMm, dVoxelMm);
        Add(a, strPrefix + "o_ring_groove_width_mm", cem.ORingGrooveWidthMm, dVoxelMm);
        Add(a, strPrefix + "lug_radius_mm", cem.LugRadiusMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(MechanicalLockCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        Add(a, strPrefix + "barb_height_mm", cem.BarbHeightMm, dVoxelMm);
        Add(a, strPrefix + "groove_depth_mm", cem.GrooveDepthMm, dVoxelMm);
        Add(a, strPrefix + "groove_width_mm", cem.GrooveWidthMm, dVoxelMm);
        Add(a, strPrefix + "bore_diameter_mm", cem.BoreDiameterMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(Zone2SleeveCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        Add(a, strPrefix + "wall_thickness_mm", cem.WallThicknessMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(TiCoinCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        Add(a, strPrefix + "disc_thickness_mm", cem.DiscThicknessMm, dVoxelMm);
        Add(a, strPrefix + "loop_tube_radius_mm", cem.LoopTubeRadiusMm, dVoxelMm);
        return a;
    }

    // Composites carry the OUTER voxel into every nested part — that inheritance is the whole defect
    // class, so it is the one thing this function must not get wrong.
    internal static IReadOnlyList<Feature> Features(AnchorAssemblyCem cem, double dVoxelMm, string strPrefix = "")
    {
        var a = new List<Feature>();
        a.AddRange(Features(cem.Flange, dVoxelMm, strPrefix + "flange."));
        a.AddRange(Features(cem.Radome, dVoxelMm, strPrefix + "radome."));
        Add(a, strPrefix + "skirt_clearance_mm", cem.SkirtClearanceMm, dVoxelMm);
        return a;
    }

    internal static IReadOnlyList<Feature> Features(AnchorAxialStackCem cem, double dVoxelMm)
    {
        var a = new List<Feature>();
        a.AddRange(Features(cem.Zone1, dVoxelMm, "zone1."));
        a.AddRange(Features(cem.Zone2, dVoxelMm, "zone2."));
        a.AddRange(Features(cem.Capsule, dVoxelMm, "capsule."));
        // 🔴 The feature the incident was about, and it exists in no manifest: the rod threads the
        // flange's channel, and what has to fit between them is the annulus, not either diameter.
        double dRod = cem.Zone1.BusRodDiameterMm, dChannel = cem.Capsule.Flange.BoreDiameterMm;
        if (dRod > 0.0 && dChannel > dRod)
            Add(a, "capsule.flange.rod_channel_annulus", (dChannel - dRod) / 2.0, dVoxelMm, bDerived: true);
        return a;
    }
}
