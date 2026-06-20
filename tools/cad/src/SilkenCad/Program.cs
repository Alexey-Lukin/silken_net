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
                    return Report(cem.Name, cem.VoxelSizeMm, voxAnode, voxEnv, cem.PorosityTarget);
                });
            }
            default:
                return Fail($"unknown CEM kind: {Cem.Kind(strJson)}");
        }
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
            "  verify <cem.json> measure golden-metrics → out/<name>.metrics.json (exit 0/1)");
        return 0;
    }

    private static int Fail(string strMsg)
    {
        Console.Error.WriteLine(strMsg);
        return 2;
    }
}
