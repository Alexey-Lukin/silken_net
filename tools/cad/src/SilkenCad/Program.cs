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
                "scan" => args.Length >= 2 ? Scan(args[1]) : Fail("usage: scan <cem.json>"),
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
            case "mechanical_lock":
            {
                MechanicalLockCem cem = Cem.Parse<MechanicalLockCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(MechanicalLock.Build(cem), cem.Name));
            }
            case "cathode_flange":
            {
                CathodeFlangeCem cem = Cem.Parse<CathodeFlangeCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(CathodeFlange.Build(cem), cem.Name));
            }
            case "radome":
            {
                RadomeCem cem = Cem.Parse<RadomeCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(Radome.Build(cem), cem.Name));
            }
            case "anchor_assembly":
            {
                AnchorAssemblyCem cem = Cem.Parse<AnchorAssemblyCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(Assembly.Build(cem).Merged, cem.Name));
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
                return RunHeadless(cem.VoxelSizeMm, () => ReportCoin(cem, TiCoin.Build(cem)));
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
            case "mechanical_lock":
            {
                MechanicalLockCem cem = Cem.Parse<MechanicalLockCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportLock(cem, MechanicalLock.Build(cem)));
            }
            case "cathode_flange":
            {
                CathodeFlangeCem cem = Cem.Parse<CathodeFlangeCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportFlange(cem, CathodeFlange.Build(cem)));
            }
            case "radome":
            {
                RadomeCem cem = Cem.Parse<RadomeCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportRadome(cem, Radome.Build(cem)));
            }
            case "anchor_assembly":
            {
                AnchorAssemblyCem cem = Cem.Parse<AnchorAssemblyCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportAssembly(cem, Assembly.Build(cem)));
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

    // wallParam critical-threshold scan (ARCH.25 / HW.33): sweep the gyroid wall band → the CEM working
    // window (the wallParam range that stays printable, open-pore and percolating). Pure (Connectivity is
    // display-less) → no Library.Go. Output → out/<name>.wallscan.json + a stdout table.
    private static int Scan(string strCemPath)
    {
        string strJson = File.ReadAllText(strCemPath);
        if (Cem.Kind(strJson) != "anchor_zone1")
            return Fail("scan needs an anchor_zone1 CEM");
        AnchorCem cem = Cem.Parse<AnchorCem>(strJson);

        WallScanResult oR = WallScan.Run(cem, fLo: 0.2f, fHi: 1.8f, fStep: 0.1f);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.wallscan.json");
        WallScan.WriteJson(oR, strPath);

        Console.WriteLine($"wallParam scan → {strPath}  (topology={cem.Topology}, core period={cem.GyroidPeriodMm} mm)");
        Console.WriteLine("  wall  porosity  open   solid-disc  perc  window");
        foreach (WallScanPoint p in oR.Points)
        {
            bool[] a = p.PorePercolates;
            string strPerc = a.Length == 3 ? $"{(a[0] ? "X" : "-")}{(a[1] ? "Y" : "-")}{(a[2] ? "Z" : "-")}" : "?";
            Console.WriteLine(
                $"  {p.WallParam:F2}  {p.Porosity,7:P1}  {p.OpenPorosity,5:P0}  {p.SolidDisconnectedFraction,8:P1}   {strPerc}   {(p.InWindow ? "✓" : "")}");
        }

        if (oR.WallMin is { } dMin && oR.WallMax is { } dMax)
            Console.WriteLine($"  working window: wallParam ∈ [{dMin:F2}, {dMax:F2}] (porosity 55–75 %, open ≥95 %, solid-disc ≤2 %, percolating)");
        else
            Console.WriteLine("  ⚠ no working window in the swept range — widen the scan or revisit period / topology");

        return oR.WallMin is not null ? 0 : 1;
    }

    // Ti-coin verify (01_01 §6.1): golden metrics + the A_electrode ≈ 2 cm² gate (01_03 §3.5). Area is the
    // PROJECTED disc face (or the defined active window) — the j = I/A normalisation surface, NOT the rough
    // wetted area. The coupon must also ENCLOSE the window (a defined area can't exceed the disc).
    private static int ReportCoin(TiCoinCem cem, Voxels voxCoin)
    {
        GeometryMetrics oM = Validation.MeasureCoin(cem, voxCoin);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        float fWindowMm = cem.ActiveWindowDiameterMm > 0f ? cem.ActiveWindowDiameterMm : cem.DiscDiameterMm;
        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine($"  active area={oM.ActiveElectrodeAreaCm2:F2} cm² (window Ø{fWindowMm:F1} mm, target 2.0 cm²)");

        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bArea = oM.ActiveElectrodeAreaCm2 is { } dA && Math.Abs(dA - 2.0) <= 0.1;   // A_electrode 2 cm² ±5%
        bool bEncloses = fWindowMm <= cem.DiscDiameterMm + 1e-4f;                        // coupon contains the window

        if (!bArea) Console.WriteLine("  ⚠ active area outside 2.0 cm² ±0.1 — tune disc / window Ø (01_03 §3.5)");
        if (!bEncloses) Console.WriteLine($"  ⚠ window Ø{fWindowMm:F1} > disc Ø{cem.DiscDiameterMm:F1} — window must fit on the coupon");

        bool bOk = bSane && bArea && bEncloses;
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

    // Mechanical-lock verify (01_01 §4.3): golden barb metrics → metrics.json + the CI gate. Barb
    // geometry (count/height/base/groove) is FAIL-gated against §4.3; self-support is INFORMATIONAL —
    // an orientation/bench call, and Ti64 LPBF self-supports the 60° downface (Sa≈15µm) anyway.
    private static int ReportLock(MechanicalLockCem cem, Voxels voxShank)
    {
        GeometryMetrics oM = Validation.MeasureLock(cem, voxShank);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  barbs={oM.BarbCount} (rows {cem.BarbRows})  h={oM.MaxBarbHeightMm:F3} mm  " +
            $"base={oM.BarbBaseMm:F3} mm  groove={oM.GrooveDepthMm:F3} mm  self-support={oM.SelfSupportFaceDeg:F0}° from horizontal");

        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bCount = oM.BarbCount == cem.BarbRows;
        bool bHeight = oM.MaxBarbHeightMm is >= 0.25 and <= 0.40;
        bool bBase = oM.BarbBaseMm is >= 0.40 and <= 0.60;
        bool bGroove = oM.GrooveDepthMm is { } dG && Math.Abs(dG - cem.GrooveDepthMm) <= (2f * cem.VoxelSizeMm) + 0.05;

        if (!bCount) Console.WriteLine($"  ⚠ barb count {oM.BarbCount} ≠ rows {cem.BarbRows}");
        if (!bHeight) Console.WriteLine("  ⚠ barb height outside §4.3 A 0.25–0.40 mm");
        if (!bBase) Console.WriteLine("  ⚠ barb base outside §4.3 A 0.40–0.60 mm (base = h·(cot α + cot β) — tune h)");
        if (!bGroove) Console.WriteLine($"  ⚠ groove depth {oM.GrooveDepthMm:F3} ≠ §4.3 B target {cem.GrooveDepthMm:F2} mm");

        // Manufacturability (informational, not FAIL-gated): recommended build orientation + the
        // integrated-anchor caveat (HW.26). ≥45° ⇒ self-supporting on the gentle-ramp-down orientation.
        if (oM.SelfSupportFaceDeg is >= 45.0)
            Console.WriteLine(
                $"  ℹ print gentle-ramp-DOWN (01_02 §1.6 tip-down) → {oM.SelfSupportFaceDeg:F0}° downface self-supports (Ti64 LPBF Sa≈15µm); " +
                "Zone-1/Zone-3 are SEPARATE prints (PEEK press-fit) ⇒ each orients freely, no co-orientation conflict");
        else
            Console.WriteLine(
                $"  ⚠ barb not self-supporting either orientation ({oM.SelfSupportFaceDeg:F0}° < 45°) — needs support or a ≤45°-from-axis ramp");

        double dRShank = cem.ShankDiameterMm / 2f, dRBore = cem.BoreDiameterMm / 2f;
        double dCylVol = Math.PI * ((dRShank * dRShank) - (dRBore * dRBore)) * cem.ShankLengthMm;
        bool bSolid = oM.SolidVolumeMm3 > 0.8 * dCylVol;   // a FILLED hollow shank (annulus), not an SDF narrow-band shell
        if (!bSolid) Console.WriteLine($"  ⚠ solid volume {oM.SolidVolumeMm3:F0} ≪ {dCylVol:F0} mm³ expected — hollow render (SDF narrow-band)");

        bool bOk = bSane && bCount && bHeight && bBase && bGroove && bSolid;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Cathode-flange verify (Деталь 3, 01_01 §1): golden metrics + assembly gates — solidity (a SOLID
    // flange, not an SDF hollow-shell, gotcha #9), Ø25 frozen, bayonet lugs fused (bbox extends past the
    // flange rim), barbs present (BoolAdd from the §4.3 lock), bus bore. Cathode side-area is informational.
    private static int ReportFlange(CathodeFlangeCem cem, Voxels voxFlange)
    {
        GeometryMetrics oM = Validation.MeasureFlange(cem, voxFlange);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  flange Ø{cem.FlangeDiameterMm:F0} · barbs={oM.BarbCount} · bayonet lugs={oM.BayonetLugCount} · " +
            $"cathode side={oM.ActiveCathodeAreaCm2:F2} cm²");

        float fFlangeR = cem.FlangeDiameterMm / 2f;
        // 3 lugs at 120° are ASYMMETRIC → only ONE extends a given axis, so the bbox span is
        // (flange + one lug tip) ≈ flangeD + protrusion, never + 2·protrusion. Confirm the lugs
        // push the bbox past the bare flange (≥ half a protrusion, robust to lug count/voxel).
        float fLugSpanMin = cem.FlangeDiameterMm + (0.5f * cem.LugProtrusionMm);
        double dFlangeVol = Math.PI * fFlangeR * fFlangeR * cem.FlangeThicknessMm;

        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bSolid = oM.SolidVolumeMm3 > 0.8 * dFlangeVol;   // a FILLED flange (+shank), not an SDF narrow-band shell
        double dMaxXY = Math.Max(oM.BboxSizeMm[0], oM.BboxSizeMm[1]);
        bool bLugs = dMaxXY >= fLugSpanMin && oM.BayonetLugCount == cem.BayonetLugs;
        bool bBarbs = oM.BarbCount == cem.BarbRows;

        if (!bSolid) Console.WriteLine($"  ⚠ solid volume {oM.SolidVolumeMm3:F0} ≪ flange {dFlangeVol:F0} mm³ — hollow render (SDF narrow-band, gotcha #9)");
        if (!bLugs) Console.WriteLine($"  ⚠ bayonet lugs not fused (max bbox {dMaxXY:F1} < expected ≥{fLugSpanMin:F1} mm)");
        if (!bBarbs) Console.WriteLine($"  ⚠ barb count {oM.BarbCount} ≠ rows {cem.BarbRows}");

        bool bOk = bSane && bSolid && bLugs && bBarbs;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Radome verify (Деталь 4, 02_01 §5.2): HOLLOW-shell gates (gotcha #9 INVERTED) — hollow fraction
    // (a real shell, not a solid block), bell rise (shield cap ≥ BellRiseMm, 01_04 §5.5), cavity height
    // (antenna↔Ti ≥12 mm, 02_01 §5.3), bayonet socket mate-fit (slot ≥ lug + clearance).
    private static int ReportRadome(RadomeCem cem, Voxels voxRadome)
    {
        GeometryMetrics oM = Validation.MeasureRadome(cem, voxRadome);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  dome Ø{cem.DomeDiameterMm:F0} · wall {cem.WallThicknessMm:F1} · hollow={oM.HollowFraction:P0} · " +
            $"bell rise={oM.BellRiseMm:F1} mm · cavity={cem.CavityHeightMm:F0} mm");

        float fSocketSlot = cem.LugRadiusMm + cem.SlotClearanceMm;
        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bHollow = oM.HollowFraction is > 0.5;                          // a real shell, NOT a solid block (gotcha #9 inverted)
        bool bBell = oM.BellRiseMm is { } dB && dB >= cem.BellRiseMm - (2f * cem.VoxelSizeMm);
        bool bCavity = cem.CavityHeightMm >= 12f;                           // antenna↔Ti RF clearance (02_01 §5.3)
        bool bMate = fSocketSlot >= cem.LugRadiusMm + 0.1f;                 // socket admits the Деталь-3 lug + clearance

        if (!bHollow) Console.WriteLine($"  ⚠ hollow fraction {oM.HollowFraction:P0} ≤ 50 % — radome rendered solid (cavity subtract failed)");
        if (!bBell) Console.WriteLine($"  ⚠ bell rise {oM.BellRiseMm:F1} < {cem.BellRiseMm:F1} mm (01_04 §5.5 anti-overgrowth)");
        if (!bCavity) Console.WriteLine($"  ⚠ cavity height {cem.CavityHeightMm:F0} < 12 mm — antenna↔Ti RF clearance (02_01 §5.3)");
        if (!bMate) Console.WriteLine($"  ⚠ socket slot {fSocketSlot:F1} < lug {cem.LugRadiusMm:F1} + clearance — bayonet mate-fit");

        bool bOk = bSane && bHollow && bBell && bCavity && bMate;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Assembly mate-audit (Деталь 3↔4, 02_02 §4): an AUDIT table, NOT a part pass/fail. The bayonet-Z / RF
    // / radial mismatches are the real un-reconciled Z-stack (HW.8/HW.17), surfaced as ⚠ + asserted by the
    // pure xUnit suite — so the exit-code gates ONLY that the merge rendered (catches a broken transform /
    // Bool), keeping CI green while the findings drive the bench reconcile.
    private static int ReportAssembly(AnchorAssemblyCem cem, AssemblyVoxels av)
    {
        GeometryMetrics oM = Validation.MeasureAssembly(cem, av);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        Console.WriteLine($"metrics → {strPath}  (mate strategy: {cem.MateStrategy})");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  bayonet-Z mismatch={oM.BayonetZMismatchMm:F2} mm · radial gap={oM.MateRadialGapMm:F2} mm · " +
            $"RF clearance={oM.RfClearanceMm:F1} mm · interference={oM.MateInterferenceMm3:F0} mm³ · lug Ø{oM.LugTipDiameterMm:F0}");

        // Render sanity — the ONLY exit-gate: a broken transform / Bool yields an empty or degenerate merge.
        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);

        // Mate findings (INFORMATIONAL — drive HW.17/HW.8, do NOT fail the audit). MATE-Ø is gated on the
        // RENDERED interference (the candidate's actual state), not the analytic gap (the baseline reason):
        // asis/inboard still foul (disc Ø25 in the Ø21 cavity), skirt opens cavity + L-slots the lugs → ~0.
        if (oM.MateInterferenceMm3 is > 5.0)
            Console.WriteLine($"  ⚠ MATE-Ø: parts foul ({oM.MateInterferenceMm3:F0} mm³ overlap) — Ø25 disc in the Ø{cem.Radome.DomeDiameterMm - (2f * cem.Radome.WallThicknessMm):F0} cavity and/or Ø29 lugs (skirt opens BOTH, inboard only the lugs; HW.17)");
        if (oM.RfClearanceMm is { } dRf && dRf < cem.RfClearanceMinMm)
            Console.WriteLine($"  ⚠ RF: antenna↔Ti {dRf:F1} < {cem.RfClearanceMinMm:F0} mm at the bayonet datum — Z-stack pulls the cavity onto the flange (02_01 §5.3)");
        if (oM.BayonetZMismatchMm is { } dBz && dBz > 2f * cem.VoxelSizeMm)
            Console.WriteLine($"  ⚠ bayonet-Z: rim lands {dBz:F2} mm off the O-ring target — Деталь3 lug-Z ↔ Деталь4 lock-groove-Z un-reconciled (HW.8)");

        Console.WriteLine(bSane
            ? "AUDIT OK — assembly rendered; mate findings above → HW.17 / HW.8 reconcile"
            : "AUDIT FAILED — merge did not render (broken transform / Bool)");
        return bSane ? 0 : 1;
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
            "  build <cem.json>  generate an STL from a CEM manifest (ti_coin | anchor_zone1 | mechanical_lock | cathode_flange | radome | anchor_assembly)\n" +
            "  verify <cem.json> measure golden-metrics → out/<name>.metrics.json (exit 0/1)\n" +
            "  sweep             generate + verify every cem/anchor_zone1.*.json (5-SKU)\n" +
            "  scan <cem.json>   wallParam working-window scan (anchor) → out/<name>.wallscan.json");
        return 0;
    }

    private static int Fail(string strMsg)
    {
        Console.Error.WriteLine(strMsg);
        return 2;
    }
}
