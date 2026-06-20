namespace SilkenCad.Tests;

// wallParam scan golden tests (ARCH.25 / HW.33) — pure-managed (Connectivity, no PicoGK Library.Go),
// on a short rod for speed. Mirrors AnchorTests' connectivity cases.
public class ScanTests
{
    // Standard Ø11 rod, shortened so adaptive sampling stays honest but fast.
    private static AnchorCem Rod() => new() { OuterDiameterMm = 11f, BoreDiameterMm = 1.6f, LengthMm = 8f, Name = "scan_test" };

    [Fact]
    public void Scan_Finds_A_Nonempty_Working_Window()
    {
        WallScanResult oR = WallScan.Run(Rod(), fLo: 0.6f, fHi: 1.2f, fStep: 0.2f);
        Assert.NotNull(oR.WallMin);
        Assert.NotNull(oR.WallMax);
        Assert.True(oR.WallMin <= oR.WallMax);
        Assert.Contains(oR.Points, p => p.InWindow);
    }

    [Fact]
    public void Porosity_Decreases_As_The_Wall_Band_Widens()
    {
        // A wider wall band ⇒ more solid ⇒ lower porosity — the scan must be monotone in wallParam.
        WallScanResult oR = WallScan.Run(Rod(), fLo: 0.4f, fHi: 1.4f, fStep: 0.2f);
        for (int i = 1; i < oR.Points.Length; i++)
            Assert.True(oR.Points[i].Porosity <= oR.Points[i - 1].Porosity + 1e-6,
                $"porosity rose at wallParam {oR.Points[i].WallParam:F2}: {oR.Points[i - 1].Porosity:F3} → {oR.Points[i].Porosity:F3}");
    }

    [Fact]
    public void Default_Wall_Band_Is_Open_And_Axially_Percolating()
    {
        // The default wallParam (1.0) must give a sound gyroid: open pore + an axial through-channel.
        WallScanResult oR = WallScan.Run(Rod(), fLo: 1.0f, fHi: 1.0f, fStep: 0.2f);
        WallScanPoint p = Assert.Single(oR.Points);
        Assert.True(p.OpenPorosity > 0.90, $"open={p.OpenPorosity:F3}");
        Assert.True(p.PorePercolates[2], "axial Z must percolate");
    }
}
