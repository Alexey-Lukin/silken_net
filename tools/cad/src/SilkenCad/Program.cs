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
                "verify" => args.Length >= 2
                    ? Verify(args[1], args.Contains("--write-golden"))
                    : Fail("usage: verify <cem.json> [--write-golden]"),
                "sweep" => Sweep(),
                "scan" => args.Length >= 2 ? Scan(args[1]) : Fail("usage: scan <cem.json>"),
                "draw" => args.Length >= 2 ? Draw(args[1]) : Fail("usage: draw <cem.json>"),
                // Voxel-FE elasticity (VoxelFea.cs) — pure-managed like `draw`, no Library.Go.
                "fea" => args.Length >= 2 ? Fea(args) : Fail("usage: fea <cem.json> [--step-div N] [--with-rod] [--sweep] | fea --ladder"),
                "render" => args.Length >= 2 ? Render(args[1]) : Fail("usage: render <cem.json>"),
                "section" => args.Length >= 2 ? Render(args[1], bSection: true) : Fail("usage: section <cem.json>"),
                // Falsifiable probes of KERNEL assumptions (Probe.cs) — not of our geometry.
                "probe" => args.Length >= 2 && float.TryParse(args[1], out float fPv)
                    ? RunHeadless(fPv, () => Probe.Run(fPv))
                    : Fail("usage: probe <voxel-mm>   e.g. probe 0.34 · probe 0.33"),
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

    private static int Verify(string strCemPath, bool bWriteGolden = false)
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
                    return ReportAnchor(cem, voxAnode, voxEnv, strCemPath, bWriteGolden);
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
        string[] aCems = Cem.ManifestFiles("cem", "anchor_zone1.*.json");
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

        // 🔴 The sweep bounds are TOPOLOGY-DEPENDENT, and a single hardcoded pair silently reports "no
        // working window" on a perfectly sound part of the other branch. On sheet the param is a BAND and
        // the 55–75 % porosity window sits near 0.75–1.35; on network it is a LEVEL and the same window
        // sits near −0.5…0.7 (measured 2026-09-11: porosity ≈ 66.4 − 16.2·wall). The ratified network
        // working point 0.10 is BELOW the old fixed `fLo: 0.2f`, i.e. this scan was about to answer a
        // question about a range that no longer contains the part. `stepped` is a band branch ⇒ sheet bounds.
        (float fLo, float fHi) = cem.Topology.Equals("network", StringComparison.OrdinalIgnoreCase)
            ? (-0.8f, 1.0f)
            : (0.2f, 1.8f);
        WallScanResult oR = WallScan.Run(cem, fLo, fHi, fStep: 0.1f);

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
    // (Деталь 3), then mechanical_lock, then the Zone-1 envelope card + Zone-2 sleeve. ⛔ The roster of
    // shipped kinds is the `switch` below, never this comment — a prose list of what exists rots on the
    // next kind added, and this one already did. Remaining kinds + phasing → roadmap §7.
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
                // strFile (not cem.Name) feeds the drawing's SSOT row: ti_coin.<alloy>.json's `name` field
                // ("ti_coin_7nb" etc.) does not equal its filename stem ("ti_coin.7nb") for any alloy variant
                // — see the comment on Drawing.TiCoin. Same class/fix as mechanical_lock below (HW.1, found
                // 2026-09-09: the base ti_coin.json coincidentally matched, so it went unnoticed).
                TiCoinCem cem = Cem.Parse<TiCoinCem>(strJson);
                string strFile = Path.GetFileName(strCemPath);
                strName = cem.Name; strSvg = Drawing.TiCoin(cem, strRev, strFile); fnDxf = p => Drawing.TiCoinDxf(cem, strRev, strFile, p);
                break;
            }
            case "cathode_flange":
            {
                CathodeFlangeCem cem = Cem.Parse<CathodeFlangeCem>(strJson);
                strName = cem.Name; strSvg = Drawing.CathodeFlange(cem, strRev); fnDxf = p => Drawing.CathodeFlangeDxf(cem, strRev, p);
                break;
            }
            case "mechanical_lock":
            {
                // strFile (not cem.Name) feeds the drawing's SSOT row: mechanical_lock.zone1/.zone3.json's
                // `name` field ("mechanical_lock_zone1"/"_zone3") does not equal its filename stem — same
                // class as ti_coin above (HW.1); cathode_flange is the one kind left where cem.Name still
                // happens to equal the filename stem — see the comment on Drawing.MechanicalLock.
                MechanicalLockCem cem = Cem.Parse<MechanicalLockCem>(strJson);
                string strFile = Path.GetFileName(strCemPath);
                strName = cem.Name; strSvg = Drawing.MechanicalLock(cem, strRev, strFile); fnDxf = p => Drawing.MechanicalLockDxf(cem, strRev, strFile, p);
                break;
            }
            case "anchor_zone1":
            {
                // strFile (not cem.Name) — every anchor_zone1.<sku>.json carries the underscore form
                // ("anchor_zone1_pine") where the filename uses a dot, i.e. the same false-SSOT-pointer
                // this family already paid for on ti_coin and mechanical_lock (HW.1, 2026-09-09).
                AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
                string strFile = Path.GetFileName(strCemPath);
                strName = cem.Name; strSvg = Drawing.AnchorZone1(cem, strRev, strFile); fnDxf = p => Drawing.AnchorZone1Dxf(cem, strRev, strFile, p);
                break;
            }
            case "zone2_sleeve":
            {
                Zone2SleeveCem cem = Cem.Parse<Zone2SleeveCem>(strJson);
                strName = cem.Name; strSvg = Drawing.Zone2Sleeve(cem, strRev); fnDxf = p => Drawing.Zone2SleeveDxf(cem, strRev, p);
                break;
            }
            default:
                // ⛔ `radome` is deliberately absent, and the reason is not effort: its geometry carries TWO
                // ratified-but-unapplied verdicts (flat crown R5 instead of the hemisphere · flat rim with
                // no counter-groove — 00_07 HW.33), both gated on the HW.9 board budget. A sheet issued
                // from today's generator would be wrong the moment it printed.
                return Fail($"draw: supports ti_coin | cathode_flange | mechanical_lock | anchor_zone1 | zone2_sleeve (got '{strKind}') — roadmap in tools/cad/docs/drawings_program.md");
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
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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

    // Rim period floor. ⚠ The ground it was written on is the SHEET rule (period 1 mm ⇒ wall
    // ~0.1 mm = the µ-LPBF floor). Measured 2026-09-12: on the shipped NETWORK branch the same
    // period yields a ligament of ~0.36 mm, so this threshold is ~3x STRICTER than its own
    // rationale and already clears the SLM floor of 0.2 mm. It is therefore conservative, not
    // leaky — and it rejects periods 0.28-1.0 mm that network can in fact print. Left unchanged
    // on purpose: moving it decides which geometry ships, which is a founder judgment (00_07
    // HW.33). Thickness-per-topology + its ceilings: 01_01 §5.5.
    private const float PrintablePeriodFloorMm = 1.0f;

    // Anchor verify: graded-aware golden metrics (per-shell porosity + finest period) → metrics.json,
    // plus the CI gate (sanity + DMLS floor + sane porosity band). Detailed profile asserts
    // (flat-vs-monotone, gradient present) live in the xUnit suite, not here.
    private static int ReportAnchor(AnchorCem cem, Voxels voxAnode, Voxels voxEnvelope,
                                    string? strCemPath = null, bool bWriteGolden = false)
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

        // ARCH.25 nice-to-have residual — informational only (NOT part of VERIFY OK/FAILED below; the
        // tracker item itself scopes these as "deferred (nice-to-have)", not a shipped gate).
        Console.WriteLine(
            $"  [nice-to-have] Euler-χ={oM.EulerCharacteristic} handles(b1)={oM.EulerHandles} " +
            $"{(oM.EulerSound == true ? "✓ sound" : "⚠ NEGATIVE — flood-fill/Euler-χ disagree, one of the two has a bug")}");
        Console.WriteLine(
            $"  [nice-to-have] tortuosity(path/displacement) mean={oM.TortuosityMean:F2} " +
            $"({oM.TortuositySuccesses}/{oM.TortuosityAttempts} walks converged)");
        Console.WriteLine(
            $"  [nice-to-have] as-printed (opening at SLM {TopologyCrossChecks.FloorMmFor(cem) * 1000:F0} µm wall floor " +
            $"[{(cem.SlmMinWallMm is null ? "canon default 01_01 §5.5" : "vendor, from this CEM")}], " +
            $"grid {TopologyCrossChecks.PrintGridStepMm(cem):F3} mm): " +
            $"sub-floor solid={oM.PrintFidelitySubFloorSolidFraction:P1} · " +
            $"pore clusters intent→printed {oM.PrintFidelityIntentClusters}→{oM.PrintFidelityPrintedClusters} · " +
            $"printed solid-disc={oM.PrintFidelityPrintedSolidDisconnectedFraction:P1} → " +
            (oM.PrintFidelityMatches == true
                ? "✓ topology survives"
                : "⚠ DIVERGES — the topology depends on walls thinner than the print floor"));

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
            Console.WriteLine($"  ⚠ finest period < printable floor {PrintablePeriodFloorMm:F2} mm (thickness per topology: sheet ~0.12·period, network ~0.36·period — 01_01 §5.5, HW.33)");
        if (!bPorositySane)
            Console.WriteLine("  ⚠ porosity outside the sane 40–85 % band");
        if (!bOpen)
            Console.WriteLine("  ⚠ open porosity < 95 % — closed/trapped pore (Archimedes-fail; ingrowth + EAAE de-powder risk)");
        if (!bNoIslands)
            Console.WriteLine("  ⚠ solid disconnected > 2 % — floating metal islands (DMLS defect / electrically dead anode)");
        if (!bPercolates)
            Console.WriteLine("  ⚠ pore does not percolate axially + radially — sap / flow-through blockage");
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));

        // Committed regression baseline (Golden.cs) — ⛔ it GATES only when one exists: an absent
        // baseline is silence, never a pass, and that asymmetry is deliberate. The wide sanity bands
        // above cannot see a 65 % → 72 % move; this can, and only this.
        bool bGolden = true;
        if (strCemPath is not null)
        {
            if (bWriteGolden)
                Golden.Write(strCemPath, oM, cem.VoxelSizeMm);
            else
                bGolden = Golden.Check(strCemPath, oM, cem.VoxelSizeMm);
        }

        bool bOk = bSane && bFloor && bPorositySane && bConnSound && bRodOk && bGolden;
        Console.WriteLine(bOk ? "VERIFY OK" : "VERIFY FAILED");
        return bOk ? 0 : 1;
    }

    // Mechanical-lock verify (01_01 §4.3): golden barb metrics → metrics.json + the CI gate. Barb
    // geometry (count/height/base/groove) is FAIL-gated against §4.3; self-support is INFORMATIONAL —
    // an orientation/bench call, and Ti64 LPBF self-supports the 60° downface (Sa≈15µm) anyway.
    private static int ReportLock(MechanicalLockCem cem, Voxels voxShank)
    {
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
    // (a real shell, not a solid block), bell rise (shield cap ≥ BellRiseMm, 01_04 §5.5), cavity height,
    // bayonet socket mate-fit (slot ≥ lug + clearance).
    //
    // ⛔ DECLARED CEILINGS on the cavity gate — it is the weakest one here and reads as the strongest:
    //  1. CAVITY HEIGHT IS NOT ANTENNA↔Ti CLEARANCE. The real clearance at the bayonet datum is
    //     `cavityH − lockGrooveZ − t/2` (Assembly.RfClearanceMm) = 8.0 at cavityH 13, so passing this
    //     gate says nothing about the RF constraint it used to name. And `RfClearanceMm` itself puts the
    //     antenna on the cavity CEILING by assumption (Validation.cs), i.e. on a board stack nobody froze.
    //  2. THE 12 IS OURS, NOT CANON'S. 02_01 §5.3 asks for ≥ 8 mm (10–15 desirable) on the λ/40 = 8.6
    //     ground and makes HFSS mandatory below 10; its only 12 is the OUTCOME of a proposed two-deck
    //     layout. Which number is the acceptance floor is an OPEN verdict (00_07 HW.33), settled by the
    //     UNI.10 VNA sweep — so this stays a working floor on the CEM dimension, not an RF claim.
    //  ⊕ Same mirror family as Cem.RfClearanceMinMm and 52_z_stack_tolerance.RF_ANT_TI_CLEARANCE_MIN;
    //     all three cite one canon row, and one date is ONE witness (00_05 §5).
    private static int ReportRadome(RadomeCem cem, Voxels voxRadome)
    {
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
        bool bCavity = cem.CavityHeightMm >= 12f;                           // OUR working floor on the CEM dim — read the ⛔ ceilings above
        bool bMate = fSocketSlot >= cem.LugRadiusMm + 0.1f;                 // socket admits the Деталь-3 lug + clearance

        if (!bHollow) Console.WriteLine($"  ⚠ hollow fraction {oM.HollowFraction:P0} ≤ 50 % — radome rendered solid (cavity subtract failed)");
        if (!bBell) Console.WriteLine($"  ⚠ bell rise {oM.BellRiseMm:F1} < {cem.BellRiseMm:F1} mm (01_04 §5.5 anti-overgrowth)");
        if (!bCavity) Console.WriteLine($"  ⚠ cavity height {cem.CavityHeightMm:F0} < 12 mm — OUR working floor, NOT the canon RF minimum (02_01 §5.3 asks ≥8); antenna↔Ti is cavityH − lockGrooveZ − t/2, see 00_07 HW.33");
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
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
            Console.WriteLine($"  ⚠ RF: antenna↔Ti {dRf:F1} < {cem.RfClearanceMinMm:F0} mm (OUR floor, not canon's — 02_01 §5.3 asks ≥8, HFSS below 10; 00_07 HW.33) at the bayonet datum — Z-stack pulls the cavity onto the flange");
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
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
        ReportResolution(Resolution.Features(cem, cem.VoxelSizeMm));
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
        Console.WriteLine(
            $"  liner: length={oM.LinerLengthMm:F1} mm (channel {AxialStack.ChannelTopZMm(cem) - AxialStack.ChannelBottomZMm(cem):F1} + " +
            $"protrusion {cem.Capsule.Flange.BusLinerProtrusionMm:F1} below the shank face) · covers channel={oM.LinerCoversChannel}");
        if (oM.LinerVolumeAnalyticMm3 is { } dAn and > 0)
            Console.WriteLine(
                $"  liner body: analytic {dAn:F2} mm³ · own voxels {oM.LinerVolumeRenderedMm3:F2} mm³ · " +
                $"ADDS TO STACK {oM.LinerAddsToStackMm3:F2} mm³ (wall {cem.Capsule.Flange.BusLinerThicknessMm:F2} mm vs voxel {cem.VoxelSizeMm:F2} mm)");

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

        if (oM.LinerCoversChannel is false)
            Console.WriteLine(
                $"  ⚠ F4: liner z[{AxialStack.LinerBottomZMm(cem):F1}, {AxialStack.LinerTopZMm(cem):F1}] does not cover channel " +
                $"z[{AxialStack.ChannelBottomZMm(cem):F1}, {AxialStack.ChannelTopZMm(cem):F1}] — bare cathode metal against the bus " +
                "at an end (01_01 §1.4; F3 judges a DIAMETER and cannot see this)");
        // 🔴 The finding this audit did NOT have until 2026-09-12, and its absence was the expensive
        // kind: the tube was BUILT, BoolAdd'ed and reported as covered while contributing zero voxels,
        // so the merged volume was byte-identical with and without it. A CEM-true body that reaches no
        // mesh is a claim nothing measures — say it out loud rather than let a reader infer geometry.
        if (oM.LinerVolumeAnalyticMm3 is { } dOwed and > 0 && (oM.LinerAddsToStackMm3 ?? 0) < 0.5 * dOwed)
            Console.WriteLine(
                $"  ⚠ the liner adds {oM.LinerAddsToStackMm3:F2} mm³ to the stack against {dOwed:F2} mm³ of analytic body — " +
                $"at this voxel ({cem.VoxelSizeMm:F2} mm) the Ø{cem.Zone1.BusRodDiameterMm:F2} rod and the " +
                $"Ø{cem.Capsule.Flange.BoreDiameterMm:F2} channel are the same voxels, so the annulus between them has " +
                "nowhere to land. F4 and the Z figures above are CEM MATH and stand; the MERGED MESH does not carry the " +
                "tube, and its own voxel volume says nothing about that (00_07 HW.34)");
        if (cem.Capsule.Flange.BusLinerThicknessMm > 0f && cem.Capsule.Flange.BusLinerProtrusionMm <= 0f)
            Console.WriteLine(
                "  ⚠ liner flush with the bore mouth — the bore EDGE then meets the tube's END FACE rather than its " +
                "flank (⚖️ 2026-09-12 ratified ≥ 1.0 mm of protrusion; 00_07 HW.34)");

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
            "  draw <cem.json>   CEM-native engineering drawing → out/<name>.drawing.svg + .dxf (ti_coin | cathode_flange | mechanical_lock | anchor_zone1 | zone2_sleeve)\n" +
            "  fea <cem.json>    voxel-FE apparent stiffness / E_solid → cache/fea/<name>.json  [--step-div N | --sweep | --with-rod]\n" +
            "  fea --ladder      size-effect ladder: the same lattice as an n-cell cube  [--cells 1,2,3,4,6,8 | --period | --wall | --sheet]\n" +
            "  fea --fit         Gibson-Ashby C and n fitted over a wall_param sweep  [--walls | --cells | --steps-per-period | --period | --sheet]");
        return 0;
    }

    // Resolution adequacy at the moment of generation (Resolution.cs, 00_07 HW.51). ⛔ It does NOT
    // gate `verify`: the HARD carrier is `ResolutionTests`, which runs on EVERY manifest in CI with no
    // display, whereas `verify` sees one part at a time and needs a render host. What the line buys is
    // the operator standing at the part — the reader `verify` has and the suite does not. One home for
    // the arithmetic, two readers; the exemption list lives with the gate, so a known row prints here
    // too rather than being silently filtered by a second copy of the policy.
    private static void ReportResolution(IReadOnlyList<Resolution.Feature> aFeatures)
    {
        foreach (Resolution.Feature f in aFeatures.Where(f => !f.Represented))
            Console.WriteLine($"  ⚠ {f.Path} spans {f.Voxels:F2} voxels ({f.ValueMm:F3} mm at voxel {f.VoxelMm:F2}) — " +
                              "below 2 the grid can drop it entirely and every metric describes a part without it");
        foreach (Resolution.Feature f in aFeatures.Where(f => f.Represented && !f.VolumeHonest))
            Console.WriteLine($"  ℹ {f.Path} spans {f.Voxels:F2} voxels — present but its measured VOLUME is coarse");
    }

    // ── Voxel-FE elasticity (00_07 HW.51 / HW.33) ────────────────────────────────────────────────
    //
    // Reports the part's APPARENT stiffness as a fraction of the solid alloy's, measured on the
    // geometry `build` would ship. ⛔ Nothing here converts that fraction into GPa: the Zone-1 alloy
    // is not selected until the Stage-2 bake-off (00_07 HW.24) and the candidates span 80–186 GPa, so
    // the ratio is the durable result and the GPa column is printed for every candidate rather than
    // for one. Pure-managed on purpose — the whole point is that it runs where `verify` cannot.
    private static int Fea(string[] args)
    {
        // ⚠️ `--fit` has TWO specimens and canon 01_01 §5.2 asks for BOTH: the lattice cube answers
        //    "what are C and n for this material", the shipped annulus answers "does the part lie on
        //    that curve at all". A coefficient measured on one is explicitly NOT transferable to the
        //    other until the two sweeps exist side by side.
        if (args.Contains("--fit"))
            return args.Length >= 2 && args[1].EndsWith(".json", StringComparison.OrdinalIgnoreCase)
                ? FeaFitPart(args) : FeaFitLattice(args);
        if (args.Contains("--ladder"))
            return FeaLadder(args);

        string strCemPath = args[1];
        string strJson = File.ReadAllText(strCemPath);
        if (Cem.Kind(strJson) != "anchor_zone1")
            return Fail($"fea: only anchor_zone1 manifests carry a lattice; {strCemPath} is '{Cem.Kind(strJson)}'");

        AnchorCem cem = Cem.Parse<AnchorCem>(strJson);
        bool bWithRod = args.Contains("--with-rod");
        int nDiv = ArgInt(args, "--step-div", 12);
        IImplicit sdf = Zone1Anode.Gyroid(cem);

        int[] aDivs = args.Contains("--sweep") ? [6, 8, 12, 16] : [nDiv];
        Console.WriteLine($"fea {cem.Name} — apparent stiffness / E_solid, ν = {VoxelFea.SolidPoissonRatio}");
        Console.WriteLine(bWithRod
            ? "  envelope: the full printed part (gyroid annulus + monolithic bus rod, 01_01 §1.4)"
            : "  envelope: the gyroid annulus only (rod excluded — comparable to the canon lattice target)");
        Console.WriteLine($"{"step,mm",9} {"elements",10} {"poros.",8} {"axial-Z",9} {"radial",9} {"islands",8} {"CG it.",8}");

        var aRows = new List<Dictionary<string, object>>();
        bool bFirstRow = true;
        foreach (int nDivisor in aDivs)
        {
            float fPeriodMin = cem.GyroidPeriodRimMm > 0f
                ? MathF.Min(cem.GyroidPeriodMm, cem.GyroidPeriodRimMm) : cem.GyroidPeriodMm;
            float fStep = fPeriodMin / nDivisor;

            Connectivity.Grid grid = VoxelFea.SampleAnchorAsBuilt(sdf, cem, fStep, bWithRod);
            Connectivity.Grid gridSolid = VoxelFea.SolidCounterpart(grid);

            VoxelFea.FeaResult oAxial = VoxelFea.ApparentAxialModulus(grid, 2);
            // 🔑 The axial divisor is analytically 1 and is NOT solved per row. The envelope is
            // prismatic along Z, so a frictionless axial compression of the fully solid grid is uniform
            // uniaxial stress at ANY step — the calibration is a property of the solver, not of the
            // resolution. Solving it per row cost more than the lattice itself (a solid grid carries
            // ~2.6× the elements) and measured 1.000000000 every time. It still RUNS once, on the
            // coarsest row, because a calibration that is only argued is not a calibration.
            double dAxialSolid = bFirstRow ? VoxelFea.ApparentAxialModulus(gridSolid, 2).StiffnessRatio : 1.0;
            VoxelFea.FeaResult oRadial = VoxelFea.RadialStiffness(grid, cem.OuterDiameterMm / 2f);
            VoxelFea.FeaResult oRadialSolid = VoxelFea.RadialStiffness(gridSolid, cem.OuterDiameterMm / 2f);
            bFirstRow = false;

            double dAxial = oAxial.StiffnessRatio;
            double dRadial = oRadial.StiffnessRatio / oRadialSolid.StiffnessRatio;
            double dPorosity = Connectivity.Porosity(grid);

            Console.WriteLine($"{fStep,9:F4} {oAxial.Elements,10:N0} {dPorosity,8:P1} {dAxial,9:F4} {dRadial,9:F4} " +
                              $"{oAxial.DiscardedIslandFraction,8:P3} {oAxial.Iterations,8:N0}");
            if (!oAxial.Converged || !oRadial.Converged)
                Console.WriteLine($"  ⚠ CG did not reach tolerance (axial residual {oAxial.Residual:E2}, radial {oRadial.Residual:E2}) — the row above is NOT a measurement");
            // The solid counterpart is a live calibration, not a formality: a frictionless uniaxial
            // test on a fully solid envelope must return E_solid exactly, so any drift here indicts
            // the element matrix or the reaction sum before it indicts the lattice.
            if (Math.Abs(dAxialSolid - 1.0) > 0.02)
                Console.WriteLine($"  ⚠ solid calibration returned {dAxialSolid:F4} of E_solid, not 1.000 — the SOLVER is off, not the lattice");

            aRows.Add(new Dictionary<string, object>
            {
                ["step_mm"] = fStep,
                ["step_divisor"] = nDivisor,
                ["elements"] = oAxial.Elements,
                ["dofs"] = oAxial.Dofs,
                ["porosity"] = dPorosity,
                ["axial_ratio"] = dAxial,
                ["radial_ratio"] = dRadial,
                ["solid_calibration_axial"] = dAxialSolid,
                ["discarded_island_fraction"] = oAxial.DiscardedIslandFraction,
                ["axial_iterations"] = oAxial.Iterations,
                ["axial_residual"] = oAxial.Residual,
                ["radial_iterations"] = oRadial.Iterations,
                ["radial_residual"] = oRadial.Residual,
                ["converged"] = oAxial.Converged && oRadial.Converged,
            });
        }

        Directory.CreateDirectory(Path.Combine("cache", "fea"));
        string strOut = Path.Combine("cache", "fea", $"{cem.Name}{(bWithRod ? ".with_rod" : "")}.json");
        File.WriteAllText(strOut, JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["_note"] = "Voxel-FE apparent stiffness of the part as MODELLED, in units of E_solid. "
                      + "Declared ceiling lives in VoxelFea.cs; a single row is an UPPER bound, read the sweep.",
            ["cem"] = cem.Name,
            ["topology"] = cem.Topology,
            ["with_bus_rod"] = bWithRod,
            ["poisson_ratio"] = VoxelFea.SolidPoissonRatio,
            ["rows"] = aRows,
        }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"→ {strOut}");
        return aRows.All(r => (bool)r["converged"]) ? 0 : 1;
    }

    // The MATERIAL-scale ladder: the same lattice in a plain cube of n periods a side, free lateral
    // surfaces, frictionless platens. Its converged rung is what Gibson-Ashby tries to predict; its
    // low rungs are where the real part lives (1.50–2.50 cells across the radial wall, 01_01 §5.2).
    // The gap between them is the size effect — measured here rather than argued.
    private static int FeaLadder(string[] args)
    {
        float fPeriod = ArgFloat(args, "--period", 2.0f);
        float fWall = ArgFloat(args, "--wall", 0.10f);
        bool bSheet = args.Contains("--sheet");
        int nStepsPerPeriod = ArgInt(args, "--steps-per-period", 12);
        int[] aCells = (ArgStr(args, "--cells", "1,2,3,4,6,8") ?? "").Split(',')
            .Select(s => int.Parse(s.Trim())).ToArray();

        Console.WriteLine($"fea --ladder — {(bSheet ? "sheet" : "network")} gyroid, period {fPeriod} mm, wall {fWall}, " +
                          $"{nStepsPerPeriod} steps/period, frictionless platens");
        Console.WriteLine($"{"cells",6} {"elements",10} {"poros.",8} {"E_app/E_solid",14}");

        var aRows = new List<Dictionary<string, object>>();
        bool bFirstRung = true;
        foreach (int nCells in aCells)
        {
            Connectivity.Grid grid = VoxelFea.SampleLatticeCube(fPeriod, fWall, !bSheet, nCells, nStepsPerPeriod);
            VoxelFea.FeaResult o = VoxelFea.ApparentAxialModulus(grid, 2);
            // Same reason as the part sweep: a fully solid cube under frictionless platens is exactly
            // E_solid at any resolution, so the divisor is 1 and only the calibration RUN is kept — on
            // the first rung, where it is cheapest and still proves the solver rather than asserting it.
            double dSolid = bFirstRung
                ? VoxelFea.ApparentAxialModulus(VoxelFea.SolidCounterpart(grid), 2).StiffnessRatio : 1.0;
            bFirstRung = false;
            double dRatio = o.StiffnessRatio;
            double dPorosity = Connectivity.Porosity(grid);
            Console.WriteLine($"{nCells,6} {o.Elements,10:N0} {dPorosity,8:P1} {dRatio,14:F4}");
            aRows.Add(new Dictionary<string, object>
            {
                ["cells_per_side"] = nCells,
                ["elements"] = o.Elements,
                ["porosity"] = dPorosity,
                ["axial_ratio"] = dRatio,
                ["solid_calibration_axial"] = dSolid,
                ["converged"] = o.Converged,
            });
        }

        Directory.CreateDirectory(Path.Combine("cache", "fea"));
        string strOut = Path.Combine("cache", "fea", $"size_effect_ladder.{(bSheet ? "sheet" : "network")}.json");
        File.WriteAllText(strOut, JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["_note"] = "Apparent axial stiffness of an n-cell cube of the same lattice, in units of E_solid. "
                      + "The converged rung is the continuum value Gibson-Ashby predicts; the low rungs are the "
                      + "regime the shipped part is in.",
            ["topology"] = bSheet ? "sheet" : "network",
            ["period_mm"] = fPeriod,
            ["wall_param"] = fWall,
            ["steps_per_period"] = nStepsPerPeriod,
            ["rows"] = aRows,
        }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"→ {strOut}");
        return aRows.All(r => (bool)r["converged"]) ? 0 : 1;
    }

    // The Gibson-Ashby COEFFICIENTS, measured instead of assumed (00_07 HW.33).
    //
    // 🔴 Why this verb is separate from `--ladder`: the ladder varies the SIZE of the specimen at one
    // density and answers "is there a size effect". This varies the DENSITY at one converged size and
    // answers "what are C and n". A single porosity cannot do the second — it pins only the product
    // C·ρⁿ at that ρ, so fixing either constant by hand determines the other, which is exactly how the
    // canon came to carry `C ≈ 1` as "an idealisation" beside `n ≈ 2` from the textbook.
    //
    // ⛔ POROSITY IS MEASURED, never derived from wall_param (01_02 §6): the wall parameter is a LEVEL
    // on a network gyroid, and the level→density map is itself resolution-dependent, so reading density
    // off the input would fold the instrument into the result.
    //
    // ⚠️ The specimen is the LATTICE CUBE, not the shipped annulus, and that is the point rather than a
    // shortcut: Gibson-Ashby is a statement about a cellular MATERIAL, so the fit must be measured on a
    // material-scale specimen. The part's own apparent stiffness is the other verb (`fea <cem>`), and
    // 01_01 §5.2 keeps the two columns apart deliberately.
    private static int FeaFitLattice(string[] args)
    {
        float fPeriod = ArgFloat(args, "--period", 2.0f);
        bool bSheet = args.Contains("--sheet");
        int nCells = ArgInt(args, "--cells", 3);
        int nStepsPerPeriod = ArgInt(args, "--steps-per-period", 16);
        float[] aWalls = (ArgStr(args, "--walls", "-0.40,-0.15,0.10,0.35,0.60") ?? "").Split(',')
            .Select(s => float.Parse(s.Trim(), System.Globalization.CultureInfo.InvariantCulture)).ToArray();

        Console.WriteLine($"fea --fit — {(bSheet ? "sheet" : "network")} gyroid, period {fPeriod} mm, " +
                          $"{nCells}-cell cube, {nStepsPerPeriod} steps/period, frictionless platens");
        Console.WriteLine($"{"wall",7} {"elements",10} {"poros.",8} {"rho",7} {"E/E_solid",11}");

        var aRows = new List<Dictionary<string, object>>();
        var aFitPoints = new List<(double Density, double Ratio)>();
        bool bFirst = true;
        double dCalibration = double.NaN;
        foreach (float fWall in aWalls)
        {
            Connectivity.Grid grid = VoxelFea.SampleLatticeCube(fPeriod, fWall, !bSheet, nCells, nStepsPerPeriod);
            VoxelFea.FeaResult o = VoxelFea.ApparentAxialModulus(grid, 2);
            // Same self-calibration contract as the ladder: a fully solid cube under frictionless
            // platens is exactly E_solid at any resolution, so the divisor is 1 and the calibration RUN
            // is kept once, as proof rather than as an assertion.
            if (bFirst)
            {
                dCalibration = VoxelFea.ApparentAxialModulus(VoxelFea.SolidCounterpart(grid), 2).StiffnessRatio;
                bFirst = false;
            }
            double dPorosity = Connectivity.Porosity(grid);
            double dRho = 1.0 - dPorosity;
            Console.WriteLine($"{fWall,7:F2} {o.Elements,10:N0} {dPorosity,8:P1} {dRho,7:F4} {o.StiffnessRatio,11:F4}");
            aFitPoints.Add((dRho, o.StiffnessRatio));
            aRows.Add(new Dictionary<string, object>
            {
                ["wall_param"] = fWall,
                ["elements"] = o.Elements,
                ["porosity"] = dPorosity,
                ["relative_density"] = dRho,
                ["axial_ratio"] = o.StiffnessRatio,
                ["converged"] = o.Converged,
            });
        }

        VoxelFea.PowerLaw fit = VoxelFea.FitPowerLaw(aFitPoints);
        Console.WriteLine($"fit  E/E_solid = {fit.C:F4}·rho^{fit.N:F3}   (R² {fit.RSquared:F4} in log space, " +
                          $"{fit.Points} points; solid calibration {dCalibration:F6})");
        foreach ((double dRho, double dE) in aFitPoints)
            Console.WriteLine($"  rho {dRho:F4}  measured {dE:F4}  fit {fit.C * Math.Pow(dRho, fit.N):F4}  " +
                              $"({(fit.C * Math.Pow(dRho, fit.N) / dE) - 1.0:+0.0%;-0.0%;0.0%})");

        Directory.CreateDirectory(Path.Combine("cache", "fea"));
        string strOut = Path.Combine("cache", "fea", $"gibson_ashby_fit.{(bSheet ? "sheet" : "network")}.s{nStepsPerPeriod}.json");
        File.WriteAllText(strOut, JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["_note"] = "Gibson-Ashby C and n fitted to MEASURED (relative density, apparent axial stiffness) "
                      + "pairs of the same lattice in a converged cube. Porosity is measured on the grid, never "
                      + "derived from wall_param. A staircase voxel mesh of fully integrated hexes is stiff-biased, "
                      + "so C is an UPPER bound; compare two steps_per_period before quoting n.",
            ["topology"] = bSheet ? "sheet" : "network",
            ["period_mm"] = fPeriod,
            ["cells_per_side"] = nCells,
            ["steps_per_period"] = nStepsPerPeriod,
            ["solid_calibration_axial"] = dCalibration,
            ["fit_c"] = fit.C,
            ["fit_n"] = fit.N,
            ["fit_r_squared_log"] = fit.RSquared,
            ["rows"] = aRows,
        }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"→ {strOut}");
        return aRows.All(r => (bool)r["converged"]) ? 0 : 1;
    }

    // The SAME sweep on the SHIPPED annulus. 01_01 §5.2 records a gap it refuses to explain away —
    // at one voxel the part reads C = 0.80 and the cube C = 0.71, i.e. the part is STIFFER at LOWER
    // density, which no monotone C·ρⁿ allows — and names this sweep, run over both geometries, as the
    // only thing that can settle it. Two candidate causes are on the record: the period gradient
    // (phase distortion, clean only to ~0.8× and the part sits exactly at 0.8) and the annulus's two
    // free surfaces. ⛔ Until both curves exist, no coefficient crosses between them.
    private static int FeaFitPart(string[] args)
    {
        string strCemPath = args[1];
        string strJson = File.ReadAllText(strCemPath);
        if (Cem.Kind(strJson) != "anchor_zone1")
            return Fail($"fea --fit: only anchor_zone1 manifests carry a lattice; {strCemPath} is '{Cem.Kind(strJson)}'");

        AnchorCem cemBase = Cem.Parse<AnchorCem>(strJson);
        bool bWithRod = args.Contains("--with-rod");
        bool bRadial = args.Contains("--with-radial");
        int nDiv = ArgInt(args, "--step-div", 12);
        float[] aWalls = (ArgStr(args, "--walls", "-0.40,-0.15,0.10,0.35,0.60") ?? "").Split(',')
            .Select(s => float.Parse(s.Trim(), System.Globalization.CultureInfo.InvariantCulture)).ToArray();

        float fPeriodMin = cemBase.GyroidPeriodRimMm > 0f
            ? MathF.Min(cemBase.GyroidPeriodMm, cemBase.GyroidPeriodRimMm) : cemBase.GyroidPeriodMm;
        float fStep = fPeriodMin / nDiv;

        Console.WriteLine($"fea --fit {cemBase.Name} — the SHIPPED annulus swept over wall_param, step {fStep:F4} mm");
        Console.WriteLine(bWithRod
            ? "  envelope: gyroid annulus + monolithic bus rod"
            : "  envelope: the gyroid annulus only (rod excluded — the lattice, comparable to the cube)");
        Console.WriteLine($"{"wall",7} {"elements",10} {"poros.",8} {"rho",7} {"axial-Z",9} {(bRadial ? "radial" : ""),9}");

        var aRows = new List<Dictionary<string, object>>();
        var aAxial = new List<(double Density, double Ratio)>();
        var aRadial = new List<(double Density, double Ratio)>();
        foreach (float fWall in aWalls)
        {
            // ⚠️ Rim follows the core deliberately: an ABSENT rim field already means "equals core"
            //    (Zone1Anode.Gyroid), so overriding only the core would silently turn a wall-uniform
            //    manifest into a wall-GRADED one and the sweep would vary two things at once.
            AnchorCem cem = cemBase with
            {
                GyroidWallParam = fWall,
                GyroidWallParamRim = cemBase.GyroidWallParamRim.HasValue ? fWall : null,
            };
            Connectivity.Grid grid = VoxelFea.SampleAnchorAsBuilt(Zone1Anode.Gyroid(cem), cem, fStep, bWithRod);
            VoxelFea.FeaResult oAxial = VoxelFea.ApparentAxialModulus(grid, 2);
            double dPorosity = Connectivity.Porosity(grid);
            double dRho = 1.0 - dPorosity;
            double dRadial = double.NaN;
            if (bRadial)
            {
                Connectivity.Grid gridSolid = VoxelFea.SolidCounterpart(grid);
                dRadial = VoxelFea.RadialStiffness(grid, cem.OuterDiameterMm / 2f).StiffnessRatio
                        / VoxelFea.RadialStiffness(gridSolid, cem.OuterDiameterMm / 2f).StiffnessRatio;
                aRadial.Add((dRho, dRadial));
            }
            Console.WriteLine($"{fWall,7:F2} {oAxial.Elements,10:N0} {dPorosity,8:P1} {dRho,7:F4} {oAxial.StiffnessRatio,9:F4} " +
                              $"{(bRadial ? dRadial.ToString("F4") : ""),9}");
            aAxial.Add((dRho, oAxial.StiffnessRatio));
            aRows.Add(new Dictionary<string, object>
            {
                ["wall_param"] = fWall,
                ["elements"] = oAxial.Elements,
                ["porosity"] = dPorosity,
                ["relative_density"] = dRho,
                ["axial_ratio"] = oAxial.StiffnessRatio,
                ["radial_ratio"] = bRadial ? dRadial : null!,
                ["converged"] = oAxial.Converged,
            });
        }

        VoxelFea.PowerLaw fitAxial = VoxelFea.FitPowerLaw(aAxial);
        Console.WriteLine($"fit axial   E/E_solid = {fitAxial.C:F4}·rho^{fitAxial.N:F3}   (R² {fitAxial.RSquared:F4} log, {fitAxial.Points} pts)");
        VoxelFea.PowerLaw? fitRadial = bRadial ? VoxelFea.FitPowerLaw(aRadial) : null;
        if (fitRadial is { } fr)
            Console.WriteLine($"fit radial  E/E_solid = {fr.C:F4}·rho^{fr.N:F3}   (R² {fr.RSquared:F4} log, {fr.Points} pts)");

        Directory.CreateDirectory(Path.Combine("cache", "fea"));
        string strOut = Path.Combine("cache", "fea", $"gibson_ashby_fit.{cemBase.Name}.d{nDiv}{(bWithRod ? ".with_rod" : "")}.json");
        File.WriteAllText(strOut, JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["_note"] = "Gibson-Ashby C and n fitted on the SHIPPED annulus, wall_param swept at one step. "
                      + "Pairs with gibson_ashby_fit.network.json (the material-scale cube): 01_01 §5.2 asks "
                      + "for both curves because a single-point C differs between them in a direction no "
                      + "monotone power law allows. Porosity is measured on the grid, never derived.",
            ["cem"] = cemBase.Name,
            ["topology"] = cemBase.Topology,
            ["with_bus_rod"] = bWithRod,
            ["step_mm"] = fStep,
            ["step_divisor"] = nDiv,
            ["fit_axial_c"] = fitAxial.C,
            ["fit_axial_n"] = fitAxial.N,
            ["fit_axial_r_squared_log"] = fitAxial.RSquared,
            ["fit_radial_c"] = fitRadial?.C!,
            ["fit_radial_n"] = fitRadial?.N!,
            ["fit_radial_r_squared_log"] = fitRadial?.RSquared!,
            ["rows"] = aRows,
        }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"→ {strOut}");
        return aRows.All(r => (bool)r["converged"]) ? 0 : 1;
    }

    private static string? ArgStr(string[] args, string strFlag, string? strDefault)
    {
        int i = Array.IndexOf(args, strFlag);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : strDefault;
    }

    private static int ArgInt(string[] args, string strFlag, int nDefault)
        => int.TryParse(ArgStr(args, strFlag, null), out int n) ? n : nDefault;

    private static float ArgFloat(string[] args, string strFlag, float fDefault)
        => float.TryParse(ArgStr(args, strFlag, null), System.Globalization.CultureInfo.InvariantCulture, out float f)
            ? f : fDefault;

    private static int Fail(string strMsg)
    {
        Console.Error.WriteLine(strMsg);
        return 2;
    }
}
