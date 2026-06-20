using System.Text.Json;

namespace SilkenCad;

// wallParam critical-threshold scan (ARCH.25 nice-to-have / HW.33). Sweeps the dimensionless gyroid
// wall band and, per value, samples the CEM's own SDF (Connectivity — pure-managed, no Library.Go) to
// map porosity + two-phase connectivity. The OUTPUT is the CEM working window: the wallParam range that
// stays printable AND open-pore AND percolating. Too thin (low wall) → the solid fragments into false
// islands / porosity runs high; too thick (high wall) → pores pinch shut (open↓, percolation lost).
// Feeds the FEA sheet-vs-network choice and bounds every SKU's safe parameter envelope.

internal sealed record WallScanPoint
{
    public required double WallParam { get; init; }
    public required double Porosity { get; init; }                  // pore / inside (render-free)
    public required double OpenPorosity { get; init; }
    public required double SolidDisconnectedFraction { get; init; }
    public required bool[] PorePercolates { get; init; }            // [X, Y, Z]
    public required bool InWindow { get; init; }
}

internal sealed record WallScanResult
{
    public required string Name { get; init; }
    public required WallScanPoint[] Points { get; init; }
    public required double? WallMin { get; init; }                  // working-window bounds; null ⇒ no window found
    public required double? WallMax { get; init; }
}

internal static class WallScan
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
    };

    // Working-window thresholds (ARCH.25 verify gates, mirrored from Program.ReportAnchor).
    private const double PorosityLo = 0.55, PorosityHi = 0.75;
    private const double OpenMin = 0.95, SolidDiscMax = 0.02;

    // Sweep wallParam ∈ [lo, hi] step `fStep`. fSampleStepMm = 0 ⇒ Connectivity's adaptive step (period/16,
    // the floor for an honest solid-island count); tests pass a coarser step on a small coupon for speed.
    public static WallScanResult Run(AnchorCem baseCem, float fLo, float fHi, float fStep, float fSampleStepMm = 0f)
    {
        var aPoints = new List<WallScanPoint>();
        double? dWallMin = null, dWallMax = null;

        for (float fWp = fLo; fWp <= fHi + (fStep / 2f); fWp += fStep)
        {
            AnchorCem cem = baseCem with { GyroidWallParam = fWp, GyroidWallParamRim = 0f };
            Connectivity.Grid grid = Connectivity.SampleAnchor(Zone1Anode.Gyroid(cem), cem, fSampleStepMm);
            ConnectivityMetrics conn = Connectivity.Analyse(grid);
            double dPorosity = Connectivity.Porosity(grid);

            bool[] aPerc = conn.PorePercolates;
            bool bWindow =
                conn.OpenPorosity >= OpenMin &&
                conn.SolidDisconnectedFraction <= SolidDiscMax &&
                aPerc.Length == 3 && aPerc[2] && (aPerc[0] || aPerc[1]) &&
                dPorosity is >= PorosityLo and <= PorosityHi;

            if (bWindow)
            {
                dWallMin ??= fWp;
                dWallMax = fWp;
            }

            aPoints.Add(new WallScanPoint
            {
                WallParam = fWp,
                Porosity = dPorosity,
                OpenPorosity = conn.OpenPorosity,
                SolidDisconnectedFraction = conn.SolidDisconnectedFraction,
                PorePercolates = aPerc,
                InWindow = bWindow,
            });
        }

        return new WallScanResult { Name = baseCem.Name, Points = [.. aPoints], WallMin = dWallMin, WallMax = dWallMax };
    }

    public static void WriteJson(WallScanResult oResult, string strPath)
        => File.WriteAllText(strPath, JsonSerializer.Serialize(oResult, Json));
}
