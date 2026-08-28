// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Numerics;
using System.Text.Json;
using System.Threading;
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
                "draw" => args.Length >= 2 ? Draw(args[1]) : Fail("usage: draw <cem.json>"),
                "render" => args.Length >= 2 ? Render(args[1]) : Fail("usage: render <cem.json>"),
                "section" => args.Length >= 2 ? Render(args[1], bSection: true) : Fail("usage: section <cem.json>"),
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
            case "zone2_sleeve":
            {
                Zone2SleeveCem cem = Cem.Parse<Zone2SleeveCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(Zone2Sleeve.Build(cem), cem.Name));
            }
            case "anchor_axial_stack":
            {
                AnchorAxialStackCem cem = Cem.Parse<AnchorAxialStackCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => Export(AxialStack.Build(cem).Merged, cem.Name));
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
            case "zone2_sleeve":
            {
                Zone2SleeveCem cem = Cem.Parse<Zone2SleeveCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportSleeve(cem, Zone2Sleeve.Build(cem)));
            }
            case "anchor_axial_stack":
            {
                AnchorAxialStackCem cem = Cem.Parse<AnchorAxialStackCem>(strJson);
                return RunHeadless(cem.VoxelSizeMm, () => ReportAxialStack(cem, AxialStack.Build(cem)));
            }
            default:
                return Fail($"unknown CEM kind: {Cem.Kind(strJson)}");
        }
    }

    // Per-species 5-SKU sweep (01_01 §6) — generates + verifies every
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

    // CEM-native engineering drawing (tools/cad/docs/drawings_program.md): analytic orthographic SVG
    // computed from the CEM numbers (no mesh, no Library.Go) — the Noyron "generator documents itself".
    // Phase 1 = ti_coin (Stage-2 coupon, the most urgent physical part); Phase 2 landed cathode_flange
    // (Деталь 3). Remaining kinds (Zone-2 sleeve, Zone-1 envelope card, assemblies) → roadmap §7.
    private static int Draw(string strCemPath)
    {
        string strJson = File.ReadAllText(strCemPath);
        string strKind = Cem.Kind(strJson);
        // 🔴 Was `?? "local"`, and "rev local" on a factory drawing is worse than no rev at all: it LOOKS
        // like a revision, so nobody asks which commit the geometry came from — while a drawing that
        // cannot be traced back to a manifest revision cannot be re-issued, compared, or blamed after a
        // bad batch. The marker is deliberately unmistakable AND actionable (it names the fix).
        string strRev = Environment.GetEnvironmentVariable("CAD_REV") is { Length: > 0 } rev
            ? rev
            : "UNTRACKED (set CAD_REV=$(git rev-parse --short HEAD))";
        Directory.CreateDirectory("out");

        // Same CEM-native pipeline per kind: SVG (human / publication / self-review) + DXF (factory
        // deliverable) computed from the CEM numbers — never the mesh. Add a kind = add a Drawing.X pair.
        string strName; string strSvg; Func<string, bool> fnDxf;
        switch (strKind)
        {
            case "ti_coin":
            {
                TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
                strName = cem.Name; strSvg = Drawing.TiCoin(cem, strRev); fnDxf = p => Drawing.TiCoinDxf(cem, strRev, p);
                break;
            }
            case "cathode_flange":
            {
                CathodeFlangeCem cem = Cem.Parse<CathodeFlangeCem>(strJson);
                strName = cem.Name; strSvg = Drawing.CathodeFlange(cem, strRev); fnDxf = p => Drawing.CathodeFlangeDxf(cem, strRev, p);
                break;
            }
            default:
                return Fail($"draw: supports ti_coin | cathode_flange (got '{strKind}') — roadmap in tools/cad/docs/drawings_program.md");
        }

        string strSvgPath = Path.Combine("out", $"{strName}.drawing.svg");
        string strDxfPath = Path.Combine("out", $"{strName}.drawing.dxf");
        File.WriteAllText(strSvgPath, strSvg);
        bool bDxf = fnDxf(strDxfPath);
        Console.WriteLine($"drawing → {strSvgPath}  (CEM-native SVG — human / publication / self-review)");
        Console.WriteLine($"drawing → {strDxfPath}  (CEM-native DXF — {(bDxf ? "factory deliverable, opens in AutoCAD/Fusion" : "SAVE FAILED")})");
        return bDxf ? 0 : 1;
    }

    // CEM → PNG via the PicoGK native viewer: build the voxels, apply a Ti-metallic material + a 3/4
    // presentation camera, screenshot. The enterprise render-as-code path (camera/material in code,
    // repeatable) — no external renderer. `section` (bSection) keeps the −X half (BoolIntersect a half-bbox
    // box) so the camera looks at the cut face → reveals INTERNAL structure (e.g. the monolithic bus rod
    // core inside the gyroid, 01_01 §1.4). Viewer-window-gated: needs a display (macOS desktop OK; CI = xvfb).
    private static int Render(string strCemPath, bool bSection = false)
    {
        string strJson = File.ReadAllText(strCemPath);
        JsonElement root = JsonDocument.Parse(strJson).RootElement;
        float fVoxel = root.TryGetProperty("voxel_size_mm", out JsonElement ve) ? ve.GetSingle() : 0.2f;
        string strName = root.TryGetProperty("name", out JsonElement ne) ? ne.GetString() ?? "render" : "render";
        string strKind = Cem.Kind(strJson);
        Directory.CreateDirectory("out");
        // PicoGK's screenshot is TGA (native, regardless of extension) → honest .tga name; the committed
        // presentation gallery converts it to PNG (GitHub-renderable). See tools/cad/scripts/render_gallery.sh.
        string strSuffix = bSection ? "_section" : "";
        string strTga = Path.GetFullPath(Path.Combine("out", $"{strName}{strSuffix}.tga"));
        if (File.Exists(strTga)) File.Delete(strTga);   // existence ⇒ fresh success

        Library.Go(fVoxel, () =>
        {
            var oV = Library.oViewer();
            oV.SetBackgroundColor(new ColorFloat(1f, 1f, 1f));

            if (bSection && strKind == "anchor_zone1")
            {
                // Reveal the monolithic bus rod (01_01 §1.4): CUT both the gyroid and the rod to the −X
                // half and point the camera at the +X cut face (Right view, deterministic — auto-frame
                // won't). The SOLID rod core (gold) sits in the centre of the gyroid cross-section (silver),
                // two opaque groups so it pops. BaseBox: Length=Z (grows +Z from frame), Width=X, Depth=Y.
                AnchorCem acem = Cem.Parse<AnchorCem>(strJson);
                Voxels voxGyroid = Zone1Anode.Anode(acem, Zone1Anode.Envelope(acem));
                BBox3 bb = voxGyroid.oCalculateBoundingBox();
                Vector3 sz = bb.vecSize(), ctr = bb.vecCenter();
                Voxels voxHalf = new BaseBox(new LocalFrame(new Vector3(bb.vecMin.X + (sz.X / 4f), ctr.Y, bb.vecMin.Z)),
                    sz.Z, sz.X / 2f, sz.Y).voxConstruct();
                voxGyroid.BoolIntersect(voxHalf);
                oV.SetGroupMaterial(0, new ColorFloat(0.72f, 0.74f, 0.78f), 0.85f, 0.35f);  // Ti-silver gyroid
                oV.Add(voxGyroid, 0);
                if (acem.BusRodDiameterMm > 0f)
                {
                    Voxels voxRod = Zone1Anode.BusRod(acem);
                    voxRod.BoolIntersect(voxHalf);
                    oV.SetGroupMaterial(1, new ColorFloat(1.0f, 0.72f, 0.05f), 0.25f, 0.7f);  // gold rod core
                    oV.Add(voxRod, 1);
                }
                oV.qOrientation = oV.qOrientationRight;   // look straight at the +X cut face
            }
            else if (bSection && strKind == "anchor_axial_stack")
            {
                // Reveal the FULL bus PATH: cut the assembled stack to the −X half + colour the through-rod
                // gold → the monolithic bus runs from the anode bottom, up the PEEK gap, through the cathode
                // channel, to the flange-top pogo pad (01_01 §1.4). Silver stack (zones) + gold through-rod.
                AxialStackVoxels s = AxialStack.Build(Cem.Parse<AnchorAxialStackCem>(strJson));
                BBox3 bb = s.Merged.oCalculateBoundingBox();
                Vector3 sz = bb.vecSize(), ctr = bb.vecCenter();
                Voxels voxHalf = new BaseBox(new LocalFrame(new Vector3(bb.vecMin.X + (sz.X / 4f), ctr.Y, bb.vecMin.Z)),
                    sz.Z, sz.X / 2f, sz.Y).voxConstruct();
                Voxels voxStack = new(s.Zone1);
                voxStack.BoolAdd(s.Zone2);
                voxStack.BoolAdd(s.Capsule);
                voxStack.BoolIntersect(voxHalf);
                oV.SetGroupMaterial(0, new ColorFloat(0.72f, 0.74f, 0.78f), 0.85f, 0.35f);  // Ti-silver stack
                oV.Add(voxStack, 0);
                if (s.Bus is { } voxBus)
                {
                    voxBus.BoolIntersect(voxHalf);
                    oV.SetGroupMaterial(1, new ColorFloat(1.0f, 0.72f, 0.05f), 0.25f, 0.7f);  // gold through-rod
                    oV.Add(voxBus, 1);
                }
                oV.qOrientation = oV.qOrientationRight;
            }
            else
            {
                Voxels vox = ConstructVoxels(strKind, strJson);
                if (bSection)
                {
                    // Generic cutaway: keep the −X half (cut face = the YZ plane through the axis).
                    // BaseBox: Length=Z (grows +Z from frame), Width=X (centred), Depth=Y.
                    BBox3 bb = vox.oCalculateBoundingBox();
                    Vector3 sz = bb.vecSize(), ctr = bb.vecCenter();
                    LocalFrame oHalf = new(new Vector3(bb.vecMin.X + (sz.X / 4f), ctr.Y, bb.vecMin.Z));
                    vox.BoolIntersect(new BaseBox(oHalf, sz.Z, sz.X / 2f, sz.Y).voxConstruct());
                }
                oV.SetGroupMaterial(0, new ColorFloat(0.72f, 0.74f, 0.78f), 0.85f, 0.35f);  // Ti-silver metallic
                oV.Add(vox, 0);
            }
            oV.RequestUpdate();
            Thread.Sleep(1500);                           // let the viewer render a frame (default auto-framed view)
            oV.RequestScreenShot(strTga);
            oV.RequestUpdate();
            Thread.Sleep(2000);                           // let the TGA be written before the app exits
        },
        strLogFilePath: "", bEndAppWithTask: true, strWindowTitle: "silkencad-render", strLightsFile: "");

        bool bOk = File.Exists(strTga);
        Console.WriteLine(bOk
            ? $"render → out/{strName}{strSuffix}.tga  (PicoGK native voxel render; TGA → PNG via scripts/render_gallery.sh)"
            : "render: no screenshot written — viewer/display issue; use f3d on the STL as fallback");
        return bOk ? 0 : 1;
    }

    // Per-kind voxel construction (mirrors Build) — shared by render; voxels need the Library.Go runtime,
    // so this runs INSIDE the task.
    private static Voxels ConstructVoxels(string strKind, string strJson) => strKind switch
    {
        "ti_coin" => TiCoin.Build(Cem.Parse<TiCoinCem>(strJson)),
        "anchor_zone1" => Zone1Anode.Build(Cem.Parse<AnchorCem>(strJson)),
        "mechanical_lock" => MechanicalLock.Build(Cem.Parse<MechanicalLockCem>(strJson)),
        "cathode_flange" => CathodeFlange.Build(Cem.Parse<CathodeFlangeCem>(strJson)),
        "radome" => Radome.Build(Cem.Parse<RadomeCem>(strJson)),
        "anchor_assembly" => Assembly.Build(Cem.Parse<AnchorAssemblyCem>(strJson)).Merged,
        "zone2_sleeve" => Zone2Sleeve.Build(Cem.Parse<Zone2SleeveCem>(strJson)),
        "anchor_axial_stack" => AxialStack.Build(Cem.Parse<AnchorAxialStackCem>(strJson)).Merged,
        _ => throw new InvalidDataException($"render: unknown CEM kind {strKind}"),
    };

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

        // Monolithic bus rod (01_01 §1.4) — MEASURE that the solid rod actually fused into the part
        // (gotcha #4 — don't assume the BoolAdd landed). voxAnode (the gyroid) is done being measured, so
        // fuse the rod onto it and re-measure: the rendered rod volume must be ≳ π(rod/2)²·L.
        bool bRodOk = true;
        if (cem.BusRodDiameterMm > 0f)
        {
            voxAnode.BoolAdd(Zone1Anode.BusRod(cem));
            voxAnode.CalculateProperties(out float fMonoVol, out BBox3 _);
            float fExpect = MathF.PI * MathF.Pow(cem.BusRodDiameterMm / 2f, 2f) * cem.LengthMm;
            float fRod = fMonoVol - (float)oM.SolidVolumeMm3;
            bRodOk = fRod > 0.5f * fExpect;
            Console.WriteLine(
                $"  monolithic bus rod Ø{cem.BusRodDiameterMm:F1}: +{fRod:F1} mm³ measured (expect ~{fExpect:F1}) → " +
                $"part {fMonoVol:F1} mm³ {(bRodOk ? "✓" : "⚠ rod missing/undersized")}");
        }

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

        bool bOk = bSane && bFloor && bPorositySane && bConnSound && bRodOk;
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
        bool bSolid = oM.SolidVolumeMm3 > 0.8 * dCylVol;   // a FILLED shank (solid, or annulus for a cathode channel), not an SDF narrow-band shell
        if (!bSolid) Console.WriteLine($"  ⚠ solid volume {oM.SolidVolumeMm3:F0} ≪ {dCylVol:F0} mm³ expected — hollow render (SDF narrow-band)");

        bool bOk = bSane && bCount && bHeight && bBase && bGroove && bSolid;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Cathode-flange verify (Деталь 3, 01_01 §1): golden metrics + assembly gates — solidity (a SOLID
    // flange, not an SDF hollow-shell, gotcha #9), Ø25 frozen, bayonet lugs fused (bbox extends past the
    // flange rim), barbs present (BoolAdd from the §4.3 lock), bus channel. Cathode side-area is informational.
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

    // Zone-2 sleeve verify (Деталь 2, 01_01 §1): hollow-tube gates — hollow (a real tube, not a solid
    // rod), OD = bore + 2·wall (the Ø15 wound, frozen), bore Ø11 (= Zone-1 shaft), length 50 (thermal
    // break §4.1). A simple part → ordinary pass/fail (unlike the audit-table assembly/stack).
    private static int ReportSleeve(Zone2SleeveCem cem, Voxels voxSleeve)
    {
        GeometryMetrics oM = Validation.MeasureSleeve(cem, voxSleeve);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        float fOd = cem.BoreDiameterMm + (2f * cem.WallThicknessMm);
        double dMaxXY = Math.Max(oM.BboxSizeMm[0], oM.BboxSizeMm[1]);
        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  bore Ø{cem.BoreDiameterMm:F0} · wall {cem.WallThicknessMm:F1} · OD Ø{fOd:F0} (wound) · " +
            $"len {cem.LengthMm:F0} · hollow={oM.HollowFraction:P0}");

        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);
        bool bHollow = oM.HollowFraction is > 0.3;                              // a real tube, not a solid rod
        bool bOd = Math.Abs(dMaxXY - fOd) <= 3f * cem.VoxelSizeMm;              // OD = wound Ø15 (frozen 01_01 §1)
        bool bLen = Math.Abs(oM.BboxSizeMm[2] - cem.LengthMm) <= 3f * cem.VoxelSizeMm;

        if (!bHollow) Console.WriteLine($"  ⚠ hollow {oM.HollowFraction:P0} ≤ 30 % — sleeve rendered solid (bore subtract failed)");
        if (!bOd) Console.WriteLine($"  ⚠ OD {dMaxXY:F1} ≠ wound Ø{fOd:F0} (bore + 2·wall, frozen 01_01 §1)");
        if (!bLen) Console.WriteLine($"  ⚠ length {oM.BboxSizeMm[2]:F1} ≠ {cem.LengthMm:F0} mm (thermal break §4.1)");

        bool bOk = bSane && bHollow && bOd && bLen;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Axial-stack mate-audit (Деталь 1↔2↔3↔4, 01_01 §1+§3): an AUDIT table, NOT a part pass/fail. The
    // press-fit findings (Zone-3 shank Ø9 ≪ bore Ø11 = clearance F1; insertion budget F2) are the real
    // un-reconciled state (HW.8), surfaced as ⚠ + asserted by the pure xUnit suite — so the exit-code
    // gates ONLY that the merge rendered, keeping CI green while the findings drive bench (as ReportAssembly).
    private static int ReportAxialStack(AnchorAxialStackCem cem, AxialStackVoxels sv)
    {
        GeometryMetrics oM = Validation.MeasureAxialStack(cem, sv);

        Directory.CreateDirectory("out");
        string strPath = Path.Combine("out", $"{cem.Name}.metrics.json");
        Validation.WriteJson(oM, strPath);

        Console.WriteLine($"metrics → {strPath}");
        Console.WriteLine(
            $"  volume={oM.SolidVolumeMm3:F1} mm^3  " +
            $"bbox={oM.BboxSizeMm[0]:F1}×{oM.BboxSizeMm[1]:F1}×{oM.BboxSizeMm[2]:F1} mm  tris={oM.TriangleCount}");
        Console.WriteLine(
            $"  press-fit Zone1↔Zone2={oM.Zone1SleeveInterferenceMm:F2} mm · Zone2↔Zone3={oM.SleeveZone3InterferenceMm:F2} mm (shank-in-bore)");
        Console.WriteLine(
            $"  render overlap: Zone1∩Zone2={oM.Zone1Zone2InterferenceMm3:F0} mm³ · sleeve∩capsule={oM.Zone2Zone3InterferenceMm3:F0} mm³ (flange shoulder on sleeve end, not the shank)");
        Console.WriteLine(
            $"  insertion budget={oM.InsertionBudgetMm:F1} mm · embedded span={oM.OverallStackLengthMm:F1} mm · " +
            $"bus-rod clears channel={oM.BusRodClears}");

        // Render sanity — the ONLY exit-gate: a broken transform / Bool yields an empty or degenerate merge.
        bool bSane = oM.SolidVolumeMm3 > 0 && oM.TriangleCount > 0 && oM.BboxSizeMm.All(d => d > 0);

        // Mate findings (INFORMATIONAL — drive HW.8, do NOT fail the audit).
        if (oM.SleeveZone3InterferenceMm is { } dS && dS < 0)
            Console.WriteLine($"  ⚠ press-fit F1: Zone-3 shank Ø{cem.Capsule.Flange.ShankDiameterMm:F0} in bore Ø{cem.Zone2.BoreDiameterMm:F0} = {-dS:F1} mm clearance/side — NO press-fit (shank Ø placeholder → HW.8)");
        if (oM.Zone1SleeveInterferenceMm is { } dZ && dZ <= 0)
            Console.WriteLine($"  ℹ Zone-1↔Zone-2 nominal line-to-line ({dZ:F2} mm) — real +interference is the H7/s6 band (bench, 01_01 §3)");
        if (oM.InsertionBudgetMm is { } dB && dB < 0)
            Console.WriteLine($"  ⚠ press-fit F2: insertion budget {dB:F1} mm < 0 — Zone-1 + Zone-3 shanks collide inside the {cem.Zone2.LengthMm:F0} mm bore");
        if (oM.BusRodClears is false)
            Console.WriteLine(cem.Zone1.BusRodDiameterMm > 0f
                ? $"  ⚠ F3: bus rod Ø{cem.Zone1.BusRodDiameterMm:F1} + 2·liner {cem.Capsule.Flange.BusLinerThicknessMm:F2} > cathode channel Ø{cem.Capsule.Flange.BoreDiameterMm:F1} — rod+insulation pinched (01_01 §1.4)"
                : $"  ⚠ F3: anode bore Ø{cem.Zone1.BoreDiameterMm:F1} < flange bore Ø{cem.Capsule.Flange.BoreDiameterMm:F1} — bus conductor pinched");

        Console.WriteLine(bSane
            ? "AUDIT OK — stack rendered; press-fit findings above → HW.8 reconcile"
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
            "  build <cem.json>  generate an STL from a CEM manifest (ti_coin | anchor_zone1 | mechanical_lock | cathode_flange | radome | zone2_sleeve | anchor_assembly | anchor_axial_stack)\n" +
            "  verify <cem.json> measure golden-metrics → out/<name>.metrics.json (exit 0/1)\n" +
            "  sweep             generate + verify every cem/anchor_zone1.*.json (5-SKU)\n" +
            "  scan <cem.json>   wallParam working-window scan (anchor) → out/<name>.wallscan.json\n" +
            "  draw <cem.json>   CEM-native engineering drawing → out/<name>.drawing.svg + .dxf (ti_coin | cathode_flange)");
        return 0;
    }

    private static int Fail(string strMsg)
    {
        Console.Error.WriteLine(strMsg);
        return 2;
    }
}
