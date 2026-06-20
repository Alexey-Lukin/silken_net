using PicoGK;
using Leap71.ShapeKernel;
using Leap71.LatticeLibrary;

namespace SilkenCad;

// SilkenNet Code-as-CAD generator CLI. A small, deterministic Computational
// Engineering Model (CEM) — geometry is computed from intent encoded in code +
// cem/*.json, in the spirit of LEAP 71 Noyron (an algorithm, not generative ML).
internal static class Program
{
    private static int Main(string[] args)
    {
        try
        {
            return (args.Length == 0 ? "help" : args[0]) switch
            {
                "smoke" => RunHeadless(0.5f, Smoke),
                "build" => args.Length >= 2 ? Build(args[1]) : Fail("usage: build <cem.json>"),
                "verify" => args.Length >= 2 ? Verify(args[1]) : Fail("usage: verify <cem.json>"),
                "sweep" => Sweep(),
                "help" or "--help" or "-h" => Help(),
                var strCmd => Fail($"unknown command: {strCmd}"),
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"error: {ex.Message}");
            return 1;
        }
    }

    // PicoGK 2.x requires geometry to run inside Library.Go's task context — the bare
    // `new Library()` headless ctor from the v1.6 docs no longer satisfies the native
    // runtime. bEndAppWithTask:true exits as soon as the task finishes, so it does NOT
    // block on the viewer window → usable for batch / CI. Exit code + any exception are
    // marshalled back out of the task thread.
    private static int RunHeadless(float fVoxelSizeMm, Func<int> fnWork)
    {
        int iResult = 2;
        Exception? oCaptured = null;
        Library.Go(
            fVoxelSizeMm,
            () =>
            {
                try { iResult = fnWork(); }
                catch (Exception ex) { oCaptured = ex; }
            },
            strLogFilePath: "",
            bEndAppWithTask: true,
            strWindowTitle: "silkencad",
            strLightsFile: "");
        if (oCaptured is not null)
            throw oCaptured;
        return iResult;
    }

    private static int Smoke()
    {
        BasePipe oPipe = new(new LocalFrame(), 20f, 4f, 8f);
        Voxels voxBounding = oPipe.voxConstruct();
        IImplicit xGyroid = new ImplicitRadialGyroid(12, 4f, 0.6f);
        _ = voxBounding.voxIntersectImplicit(xGyroid);
        Console.WriteLine("smoke OK — PicoGK + ShapeKernel + LatticeLibrary render live (headless via Library.Go).");
        return 0;
    }

    private static int Build(string strCemPath)
    {
        string strJson = File.ReadAllText(strCemPath);
        switch (Cem.Kind(strJson))
        {
            case "ti_coin":
            {
                TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(TiCoin.Build(cem), cem.Name));
            }
            case "anchor_zone1":
            {
                AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(Zone1Anode.Build(cem), cem.Name));
            }
            default:
                return Fail($"unknown CEM kind: {Cem.Kind(strJson)}");
        }
    }

    private static int Verify(string strCemPath)
    {
        string strJson = File.ReadAllText(strCemPath);
        switch (Cem.Kind(strJson))
        {
            case "ti_coin":
            {
                TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Report(cem.Name, cem.VoxelSizeMm, TiCoin.Build(cem), null));
            }
            case "anchor_zone1":
            {
                AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () =>
                {
                    Voxels voxEnv = Zone1Anode.Envelope(cem);
                    Voxels voxAnode = Zone1Anode.Anode(cem, voxEnv);
                    return ReportAnchor(cem, voxAnode, voxEnv);
                });
            }
            default:
                return Fail($"unknown CEM kind: {Cem.Kind(strJson)}");
        }
    }

    // Per-species 5-SKU sweep (00_08 §1.3) — generates + verifies every
    // cem/anchor_zone1.*.json (one Library.Go per SKU). The concrete payoff of
    // code-as-CAD over a GUI: a whole family from one generator × N manifests.
    private static int Sweep()
    {
        string[] aCems = Directory.GetFiles("cem", "anchor_zone1.*.json")
            .Where(p => !p.EndsWith(".metrics.json", StringComparison.Ordinal))
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToArray();
        if (aCems.Length == 0)
            return Fail("no cem/anchor_zone1.*.json found");

        int iRc = 0;
        foreach (string strCem in aCems)
        {
            AnchorCem cem = Cem.Parse<AnchorCem>(File.ReadAllText(strCem));
            Console.WriteLine($"--- {cem.Name} (voxel {cem.VoxelSizeMm} mm) ---");
            iRc |= RunHeadless(cem.VoxelSizeMm, () =>
            {
                Voxels voxEnv = Zone1Anode.Envelope(cem);
                Voxels voxAnode = Zone1Anode.Anode(cem, voxEnv);
                Export(voxAnode, cem.Name);
                return ReportAnchor(cem, voxAnode, voxEnv);
            });
        }
        return iRc == 0 ? 0 : 1;
    }

    private static int Report(string strName, float fVoxel, Voxels voxSolid, Voxels? voxEnvelope, float fPorosityTarget = 0f)
    {
        GeometryMetrics oMetrics = Validation.Measure(strName, fVoxel, voxSolid, voxEnvelope);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{strName}.metrics.json");
        Validation.WriteJson(oMetrics, strPath);

        string strPorosity = oMetrics.Porosity is { } dP ? $"  porosity={dP:P1} (target {fPorosityTarget:P0})" : "";
        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oMetrics.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oMetrics.BboxSizeMm[0]:F1}×{oMetrics.BboxSizeMm[1]:F1}×{oMetrics.BboxSizeMm[2]:F1} mm  " +
            $"tris={oMetrics.TriangleCount}{strPorosity}");

        // v1 sanity gate (CI-ready exit code). Richer asserts (porosity 65±2%, pore
        // gradient, min-wall) land with the graded anchor v2.
        bool bOk = oMetrics.SolidVolumeMm3 > 0 && oMetrics.TriangleCount > 0 && oMetrics.BboxSizeMm.All(d => d > 0);
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    private const float PrintablePeriodFloorMm = 1.0f;  // rim period ≥ ~1 mm ⇒ wall ≥ ~0.1 mm (µ-LPBF floor); 01_01 §5.5

    // Anchor verify: graded-aware golden metrics (per-shell porosity + finest period) → metrics.json,
    // plus the CI gate (sanity + DMLS floor + sane porosity band). Detailed profile asserts
    // (flat-vs-monotone, gradient present) live in the xUnit suite, not here.
    private static int ReportAnchor(AnchorCem cem, Voxels voxAnode, Voxels voxEnvelope)
    {
        GeometryMetrics oM = Validation.MeasureAnchor(cem, voxAnode, voxEnvelope);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        string strShells = oM.RadialPorosityByShell is { } aShell
            ? string.Join(" ", aShell.Select(p => $"{p:P0}"))
            : "";
        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  " +
            $"tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  porosity={oM.Porosity:P1} (target {cem.PorosityTarget:P0})  " +
            $"finest period={oM.FinestPeriodMm:F2} mm  shells core→rim=[{strShells}]");

        bool[] aPerc = oM.PorePercolates ?? [false, false, false];
        string strPerc = aPerc.Length == 3
            ? $"{(aPerc[0] ? "X" : "-")}{(aPerc[1] ? "Y" : "-")}{(aPerc[2] ? "Z" : "-")}"
            : "?";
        Console.WriteLine(
            $"  open={oM.OpenPorosity:P1} closed={oM.ClosedPoreFraction:P1} " +
            $"solid-disc={oM.SolidDisconnectedFraction:P1} pore-clusters={oM.PoreClusterCount} " +
            $"percolate=[{strPerc}] surface={oM.SpecificSurfaceMm2PerMm3:F2} mm2/mm3");

        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bFloor = oM.FinestPeriodMm is { } fFinest && fFinest >= PrintablePeriodFloorMm;
        bool bPorositySane = oM.Porosity is > 0.40 and < 0.85;

        // ARCH.25 connectivity gate: open pore (Archimedes), no floating metal (AM-print + electrical
        // continuity), pore percolates axially (Z = EAAE flow-through) AND ≥1 radial axis (sap/rim access).
        bool bOpen = oM.OpenPorosity is > 0.95;
        bool bNoIslands = oM.SolidDisconnectedFraction is < 0.02;
        bool bPercolates = aPerc.Length == 3 && aPerc[2] && (aPerc[0] || aPerc[1]);
        bool bConnSound = bOpen && bNoIslands && bPercolates;

        if (!bFloor)
            Console.WriteLine($"  ⚠ finest period < printable floor {PrintablePeriodFloorMm:F2} mm (wall < ~0.1 mm — µ-LPBF/nTop only, HW.33)");
        if (!bPorositySane)
            Console.WriteLine("  ⚠ porosity outside the sane 40–85 % band");
        if (!bOpen)
            Console.WriteLine("  ⚠ open porosity < 95 % — closed/trapped pore (Archimedes-fail; ingrowth + EAAE de-powder risk)");
        if (!bNoIslands)
            Console.WriteLine("  ⚠ solid disconnected > 2 % — floating metal islands (DMLS defect / electrically dead anode)");
        if (!bPercolates)
            Console.WriteLine("  ⚠ pore does not percolate axially + radially — sap / flow-through blockage");

        bool bOk = bSane && bFloor && bPorositySane && bConnSound;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    private static int Export(Voxels vox, string strName)
    {
        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{strName}.stl");
        vox.mshAsMesh().SaveToStlFile(strPath);
        Console.WriteLine($"wrote {strPath}");
        return 0;
    }

    private static int Help()
    {
        Console.WriteLine(
            "silkencad — SilkenNet Code-as-CAD (PicoGK)\n" +
            "  smoke             foundation self-test (no output file)\n" +
            "  build <cem.json>  generate an STL from a CEM manifest (ti_coin | anchor_zone1)\n" +
            "  verify <cem.json> measure golden-metrics → out/<name>.metrics.json (exit 0/1)\n" +
            "  sweep             generate + verify every cem/anchor_zone1.*.json (5-SKU)");
        return 0;
    }

    private static int Fail(string strMsg)
    {
        Console.Error.WriteLine(strMsg);
        return 2;
    }
}
