// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Text.Json;

namespace SilkenCad;

// Committed regression baseline for the GEOMETRIC metrics (00_07 HW.33/HW.49).
//
// 🔴 Why this exists, measured 2026-09-12: `out/` is gitignored, so NOTHING in the tree pinned a
// geometric number. The `verify` gates are wide sanity bands — porosity ∈ (0.40, 0.85) — while the
// figures the topology verdict rests on are 64.7–65.0 %. A change moving pine to 72 % passed green,
// and those measured values lived only as PROSE in the picogk skill, which is the form this corpus
// has already watched rot twice.
//
// ⛔ Declared ceilings, both of which decide how to read a green run:
//  1. A baseline is VOXEL- and PLATFORM-specific. It is keyed by voxel size, and a run at another
//     voxel finds no baseline and says so rather than comparing across grids.
//  2. It pins REGRESSION, never correctness. A number can be stable and wrong; what it catches is a
//     change nobody intended — which is exactly what the wide bands cannot see.
// Updating a baseline is a deliberate diff in a review, never a side effect: the file is written only
// by `verify --write-golden`, and the writer prints what moved.
internal static class Golden
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    private static string Path(string strCem) =>
        System.IO.Path.ChangeExtension(strCem, null) + ".golden.json";

    // Which metrics are worth pinning, with the tolerance each one deserves. ⚠️ The tolerances are
    // NOT uniform and that is the point: porosity is the verdict-bearing number and gets ±0.3 pp,
    // while the triangle count is meshing noise and is not pinned at all.
    private static readonly (string Key, double Tol)[] Pinned =
    [
        ("porosity", 0.003),
        ("specific_surface_mm2_per_mm3", 0.02),
        ("open_porosity", 0.005),
        ("solid_disconnected_fraction", 0.002),
        ("pore_cluster_count", 0.5),
        ("print_fidelity_sub_floor_solid_fraction", 0.003),
    ];

    public static void Write(string strCem, GeometryMetrics oM, float fVoxelMm)
    {
        Dictionary<string, object> oOut = new()
        {
            ["_note"] = "Regression baseline for `verify` — voxel-specific, pins REGRESSION not correctness "
                      + "(Golden.cs). Update only through `verify --write-golden`, and only as a reviewed diff.",
            ["voxel_size_mm"] = fVoxelMm,
        };
        foreach ((string strKey, double _) in Pinned)
            if (Value(oM, strKey) is { } dV)
                oOut[strKey] = dV;

        File.WriteAllText(Path(strCem), JsonSerializer.Serialize(oOut, Json) + "\n");
        Console.WriteLine($"  golden → {Path(strCem)} ({oOut.Count - 2} metrics at voxel {fVoxelMm:F3} mm)");
    }

    // Returns false only when a baseline EXISTS and a pinned metric left its tolerance.
    public static bool Check(string strCem, GeometryMetrics oM, float fVoxelMm)
    {
        string strPath = Path(strCem);
        if (!File.Exists(strPath))
            return true;

        using JsonDocument oDoc = JsonDocument.Parse(File.ReadAllText(strPath));
        JsonElement oRoot = oDoc.RootElement;

        if (oRoot.TryGetProperty("voxel_size_mm", out JsonElement oVox)
            && Math.Abs(oVox.GetDouble() - fVoxelMm) > 1e-6)
        {
            Console.WriteLine($"  ℹ golden baseline is for voxel {oVox.GetDouble():F3} mm, this run is "
                            + $"{fVoxelMm:F3} — NOT compared (a baseline does not cross grids)");
            return true;
        }

        bool bOk = true;
        foreach ((string strKey, double dTol) in Pinned)
        {
            if (!oRoot.TryGetProperty(strKey, out JsonElement oExp) || Value(oM, strKey) is not { } dGot)
                continue;

            double dDrift = Math.Abs(dGot - oExp.GetDouble());
            if (dDrift <= dTol)
                continue;

            Console.WriteLine($"  ⚠ GOLDEN: {strKey} = {dGot:F4} vs baseline {oExp.GetDouble():F4} "
                            + $"(drift {dDrift:F4} > tol {dTol:F4})");
            bOk = false;
        }
        Console.WriteLine(bOk ? "  golden baseline ✓" : "  ⚠ golden baseline DRIFTED — intended? `verify --write-golden`");
        return bOk;
    }

    private static double? Value(GeometryMetrics oM, string strKey) => strKey switch
    {
        "porosity" => oM.Porosity,
        "specific_surface_mm2_per_mm3" => oM.SpecificSurfaceMm2PerMm3,
        "open_porosity" => oM.OpenPorosity,
        "solid_disconnected_fraction" => oM.SolidDisconnectedFraction,
        "pore_cluster_count" => oM.PoreClusterCount,
        "print_fidelity_sub_floor_solid_fraction" => oM.PrintFidelitySubFloorSolidFraction,
        _ => null,
    };
}
