// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Globalization;
using System.Text;
using netDxf;
using netDxf.Entities;
using netDxf.Tables;

namespace SilkenCad;

// Drawing standard — TWO orthogonal axes folded into one PoC enum (projection convention + GD&T
// language; ASME Y14.5 is GD&T, NOT a projection — that's Y14.3, drawings_program.md §8). ISO =
// 1st-angle (ISO 128-30 / ISO 5456) + ISO 1101. ASME = 3rd-angle (Y14.3) + Y14.5. Default ISO
// (Ukrainian/EU shops). This replaces the hard-coded `first-angle (ISO)` footer (drift #3).
internal enum DrawingStandard { Iso, Asme }

// CEM-native engineering drawing (research → tools/cad/docs/drawings_program.md). A drawing is just
// orthographic views + dimensions + a title block — all computed ANALYTICALLY from the CEM numbers we
// already own (NOT from the lossy voxel mesh; STL→STEP→drawing loses precision + needs manual rebuild).
// Two outputs from the same CEM: SVG (human/publication/self-review) + DXF (CAD-native factory
// deliverable, opened in AutoCAD/Fusion — netDxf draws the dimensions). Deterministic, Git-friendly, no
// Library.Go, regenerates on a dim change like metrics.json — the Noyron way (the generator documents
// itself). PoC = Ti-coin (Stage 2, the most urgent physical part, 01_01 §6.1).
internal static class Drawing
{
    private const float Px = 6f;          // scale 6 px/mm (drawing scale 6:1 for a ~Ø16 part)
    private const string Stroke = "#111";
    private const string Dim = "#1166cc";

    // 🔴 The one rule this file exists to obey: a missing CEM field must print LOUDLY, never
    // plausibly. A drawing is a factory instruction — an unmarked default (`?? "Ti-6Al-4V"`) is
    // not a gap, it is a FABRICATED instruction that the shop will machine to, and neither the
    // reviewer nor the shop can tell it apart from a real one. HW.1 / picogk gotcha #11.
    // Deliberately verbose and ALL-CAPS: it must survive a glance at a printed A3.
    internal const string NotSpecified = "NOT SPECIFIED IN CEM";

    // Standard descriptor for the footer/title block (replaces the hard-coded `first-angle (ISO)`).
    private static string StandardLabel(DrawingStandard std) => std == DrawingStandard.Iso
        ? "first-angle (ISO 128/5456 · GD&T ISO 1101)"
        : "third-angle (ASME Y14.3 · GD&T Y14.5)";

    private static string N(double d) => d.ToString("0.##", CultureInfo.InvariantCulture);

    // ── SVG primitives ──
    private static string Line(double x1, double y1, double x2, double y2, string col, double w = 1, string dash = "")
        => $"<line x1='{N(x1)}' y1='{N(y1)}' x2='{N(x2)}' y2='{N(y2)}' stroke='{col}' stroke-width='{N(w)}'{(dash == "" ? "" : $" stroke-dasharray='{dash}'")}/>";
    private static string Circle(double cx, double cy, double r, string col, double w = 1, string dash = "")
        => $"<circle cx='{N(cx)}' cy='{N(cy)}' r='{N(r)}' fill='none' stroke='{col}' stroke-width='{N(w)}'{(dash == "" ? "" : $" stroke-dasharray='{dash}'")}/>";
    private static string Rect(double x, double y, double w, double h, string col, double sw = 1)
        => $"<rect x='{N(x)}' y='{N(y)}' width='{N(w)}' height='{N(h)}' fill='none' stroke='{col}' stroke-width='{N(sw)}'/>";
    private static string Text(double x, double y, string s, double size = 11, string anchor = "start", string col = "#111", string weight = "normal")
        => $"<text x='{N(x)}' y='{N(y)}' font-family='monospace' font-size='{N(size)}' text-anchor='{anchor}' fill='{col}' font-weight='{weight}'>{Esc(s)}</text>";
    private static string Esc(string s) => s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    // Centre cross-hair for a circular view.
    private static string Centre(double cx, double cy, double r, StringBuilder sb)
    {
        sb.AppendLine(Line(cx - r - 4, cy, cx + r + 4, cy, Stroke, 0.4, "6 3"));
        return Line(cx, cy - r - 4, cx, cy + r + 4, Stroke, 0.4, "6 3");
    }

    // Horizontal linear dimension with witness lines + arrow ticks + a value label above the line.
    private static void HDim(StringBuilder sb, double x1, double x2, double y, string label, double witnessFrom)
    {
        sb.AppendLine(Line(x1, witnessFrom, x1, y, Dim, 0.5));
        sb.AppendLine(Line(x2, witnessFrom, x2, y, Dim, 0.5));
        sb.AppendLine(Line(x1, y, x2, y, Dim, 0.7));
        sb.AppendLine(Line(x1, y, x1 + 4, y - 2.5, Dim, 0.7));
        sb.AppendLine(Line(x1, y, x1 + 4, y + 2.5, Dim, 0.7));
        sb.AppendLine(Line(x2, y, x2 - 4, y - 2.5, Dim, 0.7));
        sb.AppendLine(Line(x2, y, x2 - 4, y + 2.5, Dim, 0.7));
        sb.AppendLine(Text((x1 + x2) / 2, y - 3, label, 10, "middle", Dim));
    }

    // Vertical linear dimension (witness lines horizontal, label rotated-free to the right).
    private static void VDim(StringBuilder sb, double y1, double y2, double x, string label, double witnessFrom)
    {
        sb.AppendLine(Line(witnessFrom, y1, x, y1, Dim, 0.5));
        sb.AppendLine(Line(witnessFrom, y2, x, y2, Dim, 0.5));
        sb.AppendLine(Line(x, y1, x, y2, Dim, 0.7));
        sb.AppendLine(Line(x, y1, x - 2.5, y1 + 4, Dim, 0.7));
        sb.AppendLine(Line(x, y1, x + 2.5, y1 + 4, Dim, 0.7));
        sb.AppendLine(Line(x, y2, x - 2.5, y2 - 4, Dim, 0.7));
        sb.AppendLine(Line(x, y2, x + 2.5, y2 - 4, Dim, 0.7));
        sb.AppendLine(Text(x + 4, (y1 + y2) / 2 + 3, label, 10, "start", Dim));
    }

    // Title-block cell fit. The block is 250 px wide and the value column starts at +95, i.e. ~155 px —
    // about 28 monospace glyphs at font-size 9. A CEM `process` runs 89–102 chars.
    //
    // 🔴 Both previous behaviours were wrong in OPPOSITE directions, and that is the whole lesson of this
    // tract: the flange SILENTLY truncated to 22 chars (reviewer reads half a word, DXF ships the full
    // string) while the coin did not truncate at all (text overruns the 820-wide canvas and is clipped
    // mid-word by the viewport). Neither told anyone that something was missing.
    // Cure: cut at the budget and SAY SO. The full value is not lost — `Process` is already a NOTES line,
    // so the title block is a pointer, and now an honest one.
    private static string Cell(string v, int budget = 28)
        => v.Length <= budget ? v : $"{v[..(budget - 9)]}… → NOTES";

    // Title block (bottom-right grid) — part / material / scale / units / rev / notes pointer.
    private static void TitleBlock(StringBuilder sb, double x, double y, (string, string)[] rows)
    {
        const double w = 250, rh = 16;
        double h = rows.Length * rh;
        sb.AppendLine(Rect(x, y, w, h, Stroke, 1));
        for (int i = 0; i < rows.Length; i++)
        {
            double ry = y + (i * rh);
            if (i > 0) sb.AppendLine(Line(x, ry, x + w, ry, Stroke, 0.5));
            sb.AppendLine(Line(x + 90, ry, x + 90, ry + rh, Stroke, 0.5));
            sb.AppendLine(Text(x + 5, ry + 11, rows[i].Item1, 9, "start", "#555"));
            sb.AppendLine(Text(x + 95, ry + 11, rows[i].Item2, 9, "start", Stroke, "bold"));
        }
    }

    private static string Frame(double w, double h, StringBuilder body, string sha, DrawingStandard std)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"<svg xmlns='http://www.w3.org/2000/svg' width='{N(w)}' height='{N(h)}' viewBox='0 0 {N(w)} {N(h)}'>");
        sb.AppendLine($"<rect x='0' y='0' width='{N(w)}' height='{N(h)}' fill='white'/>");
        sb.AppendLine(Rect(8, 8, w - 16, h - 16, Stroke, 1.2));            // drawing border
        sb.Append(body);
        sb.AppendLine(Text(w - 14, h - 14, $"SilkenNet · CEM-native drawing · rev {sha} · units mm · scale 6:1 · {StandardLabel(std)}", 8, "end", "#888"));
        sb.AppendLine("</svg>");
        return sb.ToString();
    }

    // Notes-block lines — consume the CEM NotesSpec (Noyron-clean: the engineering text lives in the
    // CEM, not hard-coded here). `lead` is a geometry-derived first line (e.g. the computed active area).
    //
    // 🔴 TWO defects lived here and they are opposite in sign:
    //   · INVENTION — the `n is null` branch printed "Ti-6Al-4V (Grade 5)" outright, i.e. it stamped
    //     the baseline alloy onto a Ta / Au / 7Nb / CP-Ti coupon whose CEM never said so.
    //   · SILENT DROP — `Add` skipped empty values entirely, so the drawing came out COMPLETE-looking
    //     with no `Post-process: ___` line for the shop to query. A missing line is unaskable; a line
    //     reading NOT SPECIFIED IN CEM is a question the shop WILL ask before cutting metal.
    // Both are cured the same way: the field set is FIXED, and absence is printed, not skipped.
    private static List<string> NotesLines(NotesSpec? n, string? lead = null)
    {
        var lines = new List<string>();
        if (lead is not null) lines.Add(lead);
        void Add(string label, string? v) => lines.Add($"{label}: {(string.IsNullOrWhiteSpace(v) ? NotSpecified : v)}");
        Add("Material", n?.Material);
        Add("Process", n?.Process);
        Add("Surface", n?.SurfaceFinish);
        Add("Post-process", n?.PostProcess);
        Add("Coating", n?.CoatingRestriction);
        Add("Lattice", n?.LatticeSpec);
        Add("Inspect", n?.Inspection);
        if (n?.Extra is { } extra) lines.AddRange(extra);
        return lines;
    }

    // Tolerance-block lines — consume the CEM ToleranceSpec (fits / Lamé-µm / GD&T datums). Null ⇒ empty
    // (a part with no ToleranceSpec at all declares no PMI; that is a different statement from a part
    // whose spec is half-filled, and only the second one is a lie waiting to be machined).
    //
    // 🔴 The costliest single character in this file was `?? 0` in the feature line: a CEM carrying only
    // `plus_mm` rendered `"bore: 0.1/0 mm"` — a ZERO minus-tolerance the CEM never stated, in the PMI, in
    // the DXF, on the shop floor. Zero is not "unknown": it is the tightest possible limit, so the invented
    // value is not merely wrong, it is wrong in the expensive direction. Now each side prints on its own.
    //
    // 🔴 And the mirror: the feature line vanished ENTIRELY when both sides were absent, so
    // `cathode_flange.json`'s `shank_dia` (Ø9 — itself an HW.8.9 placeholder) appeared in NEITHER svg nor
    // dxf. A named feature with no limits is exactly what the shop must be told about.
    private static List<string> ToleranceLines(ToleranceSpec? t)
    {
        var lines = new List<string>();
        if (t is null) return lines;
        if (t.Fit is { } fit) lines.Add($"Fit: {fit}");
        if (t.InterferenceMinUm is { } lo && t.InterferenceMaxUm is { } hi) lines.Add($"Interference: {N(lo)}–{N(hi)} µm (Lamé, E_PEEK-aware)");
        else if (t.InterferenceMinUm is { } only) lines.Add($"Interference: min {N(only)} µm, max {NotSpecified}");
        else if (t.InterferenceMaxUm is { } onlyHi) lines.Add($"Interference: min {NotSpecified}, max {N(onlyHi)} µm");
        if (t.ClearanceMm is { } cl) lines.Add($"Clearance: ≤{N(cl)} mm");
        if (t.Feature is { } f)
        {
            string plus = t.PlusMm is { } p ? $"+{N(p)}" : NotSpecified;
            string minus = t.MinusMm is { } m ? $"-{N(m)}" : NotSpecified;
            lines.Add($"{f}: {plus} / {minus} mm");
        }
        if (t.PrimaryDatum is { } d) lines.Add($"Datum A: {d}");
        if (t.SecondaryDatum is { } d2) lines.Add($"Datum B: {d2}");
        if (t.ConcentricityMm is { } cc) lines.Add($"Concentricity: ⌀{cc} (A)");
        if (t.RunoutMm is { } ro) lines.Add($"Runout: {ro} (A)");
        return lines;
    }

    // ── Ti-coin (Stage-2 coupon, 01_01 §6.1) — front (Ø disc) + side (thickness) + eyelet + A_electrode ──
    public static string TiCoin(TiCoinCem cem, string sha, DrawingStandard std = DrawingStandard.Iso)
    {
        double r = cem.DiscDiameterMm / 2.0 * Px;
        double t = cem.DiscThicknessMm * Px;
        double frontCx = 150, cy = 150;
        double sideX = 320;                                   // left edge of the side view
        var b = new StringBuilder();

        // Title + part label
        b.AppendLine(Text(20, 30, "Ti-COIN  (Stage-2 in-vitro coupon)", 15, "start", Stroke, "bold"));
        b.AppendLine(Text(20, 46, "Деталь — EBFC test electrode · 01_01 §6.1", 10, "start", "#555"));

        // FRONT VIEW — disc circle + centre + eyelet + (optional) active-area window
        b.AppendLine(Circle(frontCx, cy, r, Stroke, 1.2));
        b.AppendLine(Centre(frontCx, cy, r, b));
        double winMm = cem.ActiveWindowDiameterMm > 0f ? cem.ActiveWindowDiameterMm : cem.DiscDiameterMm;
        if (cem.ActiveWindowDiameterMm > 0f)
            b.AppendLine(Circle(frontCx, cy, cem.ActiveWindowDiameterMm / 2.0 * Px, Dim, 0.8, "4 2"));
        // eyelet at the top edge: a small ring (loop) tangent outside the disc
        double loopR = cem.LoopRingRadiusMm * Px, tubeR = cem.LoopTubeRadiusMm * Px;
        double eyCy = cy - r - loopR;
        b.AppendLine(Circle(frontCx, eyCy, loopR + tubeR, Stroke, 1.0));
        b.AppendLine(Circle(frontCx, eyCy, loopR - tubeR > 0 ? loopR - tubeR : tubeR, Stroke, 1.0));
        b.AppendLine(Text(frontCx, cy + r + 40, "FRONT", 10, "middle", "#555"));

        // Ø dimension (under front view)
        HDim(b, frontCx - r, frontCx + r, cy + r + 22, $"Ø{N(cem.DiscDiameterMm)}", cy + r);

        // SIDE VIEW — thickness rectangle (height = disc Ø), eyelet stub
        double sideTop = cy - r;
        b.AppendLine(Rect(sideX, sideTop, t, 2 * r, Stroke, 1.2));
        b.AppendLine(Rect(sideX, eyCy - tubeR, t, 2 * tubeR, Stroke, 0.8));    // eyelet edge-on
        b.AppendLine(Text(sideX + t / 2, cy + r + 40, "SIDE", 10, "middle", "#555"));
        VDim(b, sideTop, sideTop + 2 * r, sideX + t + 26, $"Ø{N(cem.DiscDiameterMm)}", sideX + t);
        HDim(b, sideX, sideX + t, sideTop - 14, $"{N(cem.DiscThicknessMm)}", sideTop);

        // NOTES + TOLERANCES — consumed from the CEM (Noyron-clean; no hard-coded engineering text).
        double a = Math.PI * Math.Pow(winMm / 2.0, 2) / 100.0;
        string lead = $"Active electrode area ≈ {N(a)} cm² (1 face; j = I/A projected, 01_03 §3.5)"
            + (cem.ActiveWindowDiameterMm > 0f ? $"; defined-area window Ø{N(cem.ActiveWindowDiameterMm)} (dashed)" : "");
        double ny = 300;
        b.AppendLine(Text(20, ny, "NOTES:", 10, "start", Stroke, "bold"));
        var notes = NotesLines(cem.Notes, lead);
        for (int i = 0; i < notes.Count; i++) b.AppendLine(Text(20, ny + 16 + (i * 14), $"{i + 1}. {notes[i]}", 9, "start", "#333"));

        var tol = ToleranceLines(cem.Tolerances);
        if (tol.Count > 0)
        {
            double ty = ny + 16 + (notes.Count * 14) + 10;
            b.AppendLine(Text(20, ty, "TOLERANCES / GD&T:", 10, "start", Stroke, "bold"));
            for (int i = 0; i < tol.Count; i++) b.AppendLine(Text(20, ty + 16 + (i * 14), tol[i], 9, "start", "#333"));
        }

        // TITLE BLOCK — material/process/SSOT come from the CEM (the alloy-bake-off SKU), not hard-coded:
        // each ti_coin.<alloy>.json carries its own Notes.Material (01_02 §2.5).
        // 🔴 A null here used to print the 4V baseline — on a bake-off part whose whole purpose is that
        // the alloy is the VARIABLE (Ta / Au / 7Nb / CP-Ti), that default is the single most expensive
        // string in the drawing: it names the wrong metal in the box the shop reads first.
        TitleBlock(b, 540, 470, new[]
        {
            ("PART", "Ti-coin"),
            ("MATERIAL", Cell(cem.Notes?.Material ?? NotSpecified)),
            ("PROCESS", Cell(cem.Notes?.Process ?? NotSpecified)),
            ("UNITS / SCALE", "mm / 6:1"),
            ("REV", Cell(sha, 34)),
            ("SSOT", $"cem/{cem.Name}.json"),
        });

        // 🔴 Canvas 560 → 620. The title block runs 470..566 (6 rows × 16), so on a 560-tall frame its
        // LAST row — SSOT, the pointer back to the manifest — was drawn outside the viewport and simply
        // did not exist for the reviewer, while the DXF carried it. That is the inverted-risk half of
        // gotcha #11: the human sees LESS than the factory, so a bad line rides through self-review
        // precisely because it is invisible on screen.
        return Frame(820, 620, b, sha, std);
    }

    // ── DXF (CAD-native factory deliverable) — the same Ti-coin views in real mm (1:1, Y-up). netDxf
    // writes a file the shop opens in AutoCAD/Fusion. Dimension geometry is laid out manually (witness +
    // arrow Lines + a value Text) so the API surface stays Circle/Line/Text/Layer — robust, every CAD
    // reads it. `%%c` is the DXF single-line code for Ø; DxfSafe maps the few Unicode glyphs to ASCII. ──
    public static bool TiCoinDxf(TiCoinCem cem, string sha, string path, DrawingStandard std = DrawingStandard.Iso)
    {
        var doc = new DxfDocument();
        var geo = new Layer("GEOMETRY");
        var dmn = new Layer("DIMENSIONS") { Color = AciColor.Blue };
        var nte = new Layer("NOTES") { Color = AciColor.Cyan };

        double rr = cem.DiscDiameterMm / 2.0, t = cem.DiscThicknessMm, cx = 0, cy = 0;

        // FRONT — disc + centre cross + eyelet
        doc.Entities.Add(new Circle(new Vector2(cx, cy), rr) { Layer = geo });
        doc.Entities.Add(new Line(new Vector2(cx - rr - 2, cy), new Vector2(cx + rr + 2, cy)) { Layer = geo });
        doc.Entities.Add(new Line(new Vector2(cx, cy - rr - 2), new Vector2(cx, cy + rr + 2)) { Layer = geo });
        double loopR = cem.LoopRingRadiusMm, tubeR = cem.LoopTubeRadiusMm, eyCy = cy + rr + loopR;
        doc.Entities.Add(new Circle(new Vector2(cx, eyCy), loopR + tubeR) { Layer = geo });
        if (loopR - tubeR > 0) doc.Entities.Add(new Circle(new Vector2(cx, eyCy), loopR - tubeR) { Layer = geo });
        DxfHDim(doc, dmn, cx - rr, cx + rr, cy - rr - 5, $"%%c{N(cem.DiscDiameterMm)}");
        doc.Entities.Add(new Text("FRONT", new Vector2(cx - rr / 2, cy - rr - 11), 2.0) { Layer = nte });

        // SIDE — thickness rect (4 lines) + thickness dim
        double sx = rr + 16;
        var q = new[] { new Vector2(sx, cy - rr), new Vector2(sx + t, cy - rr), new Vector2(sx + t, cy + rr), new Vector2(sx, cy + rr) };
        for (int i = 0; i < 4; i++) doc.Entities.Add(new Line(q[i], q[(i + 1) % 4]) { Layer = geo });
        DxfHDim(doc, dmn, sx, sx + t, cy - rr - 5, N(t));
        doc.Entities.Add(new Text("SIDE", new Vector2(sx, cy - rr - 11), 2.0) { Layer = nte });

        // NOTES + TOLERANCES (stacked text below the views) — consumed from the CEM, same as the SVG
        double winMm = cem.ActiveWindowDiameterMm > 0f ? cem.ActiveWindowDiameterMm : cem.DiscDiameterMm;
        double a = Math.PI * Math.Pow(winMm / 2.0, 2) / 100.0;
        var lines = new List<string> { "NOTES:" };
        var nl = NotesLines(cem.Notes, $"Active electrode area ~{N(a)} cm2 (1 face, projected; 01_03 3.5)");
        for (int i = 0; i < nl.Count; i++) lines.Add($"{i + 1}. {nl[i]}");
        var tl = ToleranceLines(cem.Tolerances);
        if (tl.Count > 0) { lines.Add("TOLERANCES / GD&T:"); lines.AddRange(tl); }
        lines.Add($"SilkenNet Ti-coin | rev {sha} | mm 1:1 | {StandardLabel(std)} | SSOT cem/{cem.Name}.json");
        double yy = cy - rr - 20;
        foreach (string ln in lines) { doc.Entities.Add(new Text(DxfSafe(ln), new Vector2(cx - rr, yy), 1.6) { Layer = nte }); yy -= 3.2; }

        return doc.Save(path);
    }

    // ── Cathode flange (Деталь 3, 01_01 §1 + 02_02 §1.2) — the capsule-side anchor end. FRONT (pogo
    // face: flange Ø + GND pad + PEEK isolation ring + bore + bayonet lugs) + SIDE (flange↦shank
    // T-profile, axis horizontal). Same CEM-native pipeline as the Ti-coin; reuses every primitive. ──
    public static string CathodeFlange(CathodeFlangeCem cem, string sha, DrawingStandard std = DrawingStandard.Iso)
    {
        double rFlange = cem.FlangeDiameterMm / 2.0 * Px;
        double rPad = cem.CentralPadDiameterMm / 2.0 * Px;
        double rIso = (cem.CentralPadDiameterMm / 2.0 + cem.IsolationRingWidthMm) * Px;
        double rBore = cem.BoreDiameterMm / 2.0 * Px;
        double rLug = cem.LugRadiusMm * Px;
        double lugOut = rFlange + cem.LugProtrusionMm * Px;          // lug centreline radius
        double t = cem.FlangeThicknessMm * Px;
        double shD = cem.ShankDiameterMm * Px, shL = cem.ShankLengthMm * Px;
        double frontCx = 200, cy = 200, sideX = 430;
        var b = new StringBuilder();

        b.AppendLine(Text(20, 30, "CATHODE FLANGE  (Деталь 3 · Zone 3)", 15, "start", Stroke, "bold"));
        b.AppendLine(Text(20, 46, "Capsule-side anchor end · pogo face + bayonet · 01_01 §1 · 02_02 §1.2", 10, "start", "#555"));

        // FRONT — bayonet lugs (behind) → flange → PEEK iso ring (dashed) → GND pad → bore → centre
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            double ang = (Math.PI * 2 * i / cem.BayonetLugs) - Math.PI / 2;     // first lug at top
            b.AppendLine(Circle(frontCx + lugOut * Math.Cos(ang), cy + lugOut * Math.Sin(ang), rLug, Stroke, 1.0));
        }
        b.AppendLine(Circle(frontCx, cy, rFlange, Stroke, 1.2));
        b.AppendLine(Circle(frontCx, cy, rIso, Dim, 0.8, "4 2"));
        b.AppendLine(Circle(frontCx, cy, rPad, Stroke, 1.0));
        b.AppendLine(Circle(frontCx, cy, rBore, Stroke, 0.8));
        b.AppendLine(Centre(frontCx, cy, rFlange, b));
        b.AppendLine(Text(frontCx, cy + rFlange + 46, "FRONT (pogo face)", 10, "middle", "#555"));
        HDim(b, frontCx - rFlange, frontCx + rFlange, cy + rFlange + 24, $"Ø{N(cem.FlangeDiameterMm)}", cy + rFlange);
        b.AppendLine(Text(frontCx + rPad + 5, cy - 3, $"Ø{N(cem.CentralPadDiameterMm)} GND pad", 9, "start", Dim));
        b.AppendLine(Text(frontCx + rIso + 5, cy + 12, $"PEEK iso ring {N(cem.IsolationRingWidthMm)}", 9, "start", Dim));
        b.AppendLine(Text(frontCx + lugOut - rLug, cy - lugOut - rLug - 3, $"{cem.BayonetLugs}× bayonet lug", 9, "middle", Dim));

        // SIDE — flange (thick × Ø) ↦ shank (Ø9 × L), bore axis, bayonet lug edge-on
        double fTop = cy - rFlange, fBot = cy + rFlange, shTop = cy - shD / 2, shBot = cy + shD / 2;
        double lugT = cem.LugProtrusionMm * Px;
        b.AppendLine(Rect(sideX, fTop, t, 2 * rFlange, Stroke, 1.2));
        b.AppendLine(Rect(sideX + t, shTop, shL, shD, Stroke, 1.2));
        b.AppendLine(Rect(sideX, fTop - lugT, t, lugT, Stroke, 0.8));        // lug protrusion top
        b.AppendLine(Rect(sideX, fBot, t, lugT, Stroke, 0.8));              // lug protrusion bottom
        b.AppendLine(Line(sideX, cy, sideX + t + shL, cy, Stroke, 0.4, "6 3"));   // bore axis
        b.AppendLine(Text(sideX + (t + shL) / 2, cy + rFlange + 46, "SIDE (section)", 10, "middle", "#555"));
        HDim(b, sideX, sideX + t, fTop - lugT - 12, $"{N(cem.FlangeThicknessMm)}", fTop - lugT);
        HDim(b, sideX + t, sideX + t + shL, shBot + 22, $"{N(cem.ShankLengthMm)}", shBot);
        VDim(b, shTop, shBot, sideX + t + shL + 24, $"Ø{N(cem.ShankDiameterMm)}", sideX + t + shL);

        // NOTES + TOLERANCES — consumed from the CEM (Noyron-clean), same as the coin
        double ny = cy + rFlange + 82;
        string lead = "Cathode catalytic = side/perimeter (O₂ under radome); pogo = top face (02_02 §1.2)";
        b.AppendLine(Text(20, ny, "NOTES:", 10, "start", Stroke, "bold"));
        var notes = NotesLines(cem.Notes, lead);
        for (int i = 0; i < notes.Count; i++) b.AppendLine(Text(20, ny + 16 + (i * 14), $"{i + 1}. {notes[i]}", 9, "start", "#333"));
        var tol = ToleranceLines(cem.Tolerances);
        if (tol.Count > 0)
        {
            double ty = ny + 16 + (notes.Count * 14) + 10;
            b.AppendLine(Text(20, ty, "TOLERANCES / GD&T:", 10, "start", Stroke, "bold"));
            for (int i = 0; i < tol.Count; i++) b.AppendLine(Text(20, ty + 16 + (i * 14), tol[i], 9, "start", "#333"));
        }

        // 🔴 PROCESS was truncated to 22 chars HERE and nowhere else — so the reviewer read a half word
        // while the DXF shipped the full string. Truncation is now gone: the value either fits or the
        // drawing looks wrong, and "looks wrong" is the correct outcome for an over-long factory note.
        // (The Ti-coin block never truncated, which is why the same overflow surfaced there as clipping
        // instead — one class, two symptoms, and neither visible from the other file.)
        TitleBlock(b, 620, 470, new[]
        {
            ("PART", "Cathode flange (Деталь 3)"),
            ("MATERIAL", Cell(cem.Notes?.Material ?? NotSpecified)),
            ("PROCESS", Cell(cem.Notes?.Process ?? NotSpecified)),
            ("UNITS / SCALE", "mm / 6:1"),
            ("REV", sha),
            ("SSOT", $"cem/{cem.Name}.json"),
        });

        return Frame(900, 700, b, sha, std);
    }

    // ── Cathode-flange DXF (CAD-native factory deliverable, 1:1 mm Y-up) — same views, real mm. ──
    public static bool CathodeFlangeDxf(CathodeFlangeCem cem, string sha, string path, DrawingStandard std = DrawingStandard.Iso)
    {
        var doc = new DxfDocument();
        var geo = new Layer("GEOMETRY");
        var dmn = new Layer("DIMENSIONS") { Color = AciColor.Blue };
        var nte = new Layer("NOTES") { Color = AciColor.Cyan };

        double rF = cem.FlangeDiameterMm / 2.0, rP = cem.CentralPadDiameterMm / 2.0;
        double rIso = cem.CentralPadDiameterMm / 2.0 + cem.IsolationRingWidthMm, rB = cem.BoreDiameterMm / 2.0;
        double rL = cem.LugRadiusMm, lugOut = rF + cem.LugProtrusionMm;
        double t = cem.FlangeThicknessMm, shD = cem.ShankDiameterMm, shL = cem.ShankLengthMm, cx = 0, cy = 0;

        // FRONT — flange + iso ring + pad + bore + centre + lugs
        doc.Entities.Add(new Circle(new Vector2(cx, cy), rF) { Layer = geo });
        doc.Entities.Add(new Circle(new Vector2(cx, cy), rIso) { Layer = geo });
        doc.Entities.Add(new Circle(new Vector2(cx, cy), rP) { Layer = geo });
        doc.Entities.Add(new Circle(new Vector2(cx, cy), rB) { Layer = geo });
        doc.Entities.Add(new Line(new Vector2(cx - rF - 2, cy), new Vector2(cx + rF + 2, cy)) { Layer = geo });
        doc.Entities.Add(new Line(new Vector2(cx, cy - rF - 2), new Vector2(cx, cy + rF + 2)) { Layer = geo });
        for (int i = 0; i < cem.BayonetLugs; i++)
        {
            double ang = (Math.PI * 2 * i / cem.BayonetLugs) + Math.PI / 2;
            doc.Entities.Add(new Circle(new Vector2(cx + lugOut * Math.Cos(ang), cy + lugOut * Math.Sin(ang)), rL) { Layer = geo });
        }
        DxfHDim(doc, dmn, cx - rF, cx + rF, cy - rF - 5, $"%%c{N(cem.FlangeDiameterMm)}");
        doc.Entities.Add(new Text("FRONT (pogo face)", new Vector2(cx - rF / 2, cy - rF - 11), 2.0) { Layer = nte });

        // SIDE — flange ↦ shank T-profile (axis horizontal) + bore axis
        double sx = rF + 16;
        var fl = new[] { new Vector2(sx, cy - rF), new Vector2(sx + t, cy - rF), new Vector2(sx + t, cy + rF), new Vector2(sx, cy + rF) };
        for (int i = 0; i < 4; i++) doc.Entities.Add(new Line(fl[i], fl[(i + 1) % 4]) { Layer = geo });
        var sh = new[] { new Vector2(sx + t, cy - shD / 2), new Vector2(sx + t + shL, cy - shD / 2), new Vector2(sx + t + shL, cy + shD / 2), new Vector2(sx + t, cy + shD / 2) };
        for (int i = 0; i < 4; i++) doc.Entities.Add(new Line(sh[i], sh[(i + 1) % 4]) { Layer = geo });
        doc.Entities.Add(new Line(new Vector2(sx, cy), new Vector2(sx + t + shL, cy)) { Layer = geo });
        DxfHDim(doc, dmn, sx + t, sx + t + shL, cy - shD / 2 - 5, N(cem.ShankLengthMm));
        DxfHDim(doc, dmn, sx, sx + t, cy + rF + 4, N(cem.FlangeThicknessMm));
        doc.Entities.Add(new Text("SIDE", new Vector2(sx, cy - rF - 11), 2.0) { Layer = nte });

        // NOTES + TOLERANCES stacked below
        var lines = new List<string> { "NOTES:" };
        var nl = NotesLines(cem.Notes, "Cathode catalytic = side/perimeter (O2 under radome); pogo = top face (02_02 1.2)");
        for (int i = 0; i < nl.Count; i++) lines.Add($"{i + 1}. {nl[i]}");
        var tl = ToleranceLines(cem.Tolerances);
        if (tl.Count > 0) { lines.Add("TOLERANCES / GD&T:"); lines.AddRange(tl); }
        lines.Add($"SilkenNet cathode flange | rev {sha} | mm 1:1 | {StandardLabel(std)} | SSOT cem/{cem.Name}.json");
        double yy = cy - rF - 20;
        foreach (string ln in lines) { doc.Entities.Add(new Text(DxfSafe(ln), new Vector2(cx - rF, yy), 1.6) { Layer = nte }); yy -= 3.2; }

        return doc.Save(path);
    }

    // Manual horizontal linear dimension in DXF: two short extension ticks + a dimension line + a value.
    private static void DxfHDim(DxfDocument doc, Layer layer, double x1, double x2, double y, string label)
    {
        doc.Entities.Add(new Line(new Vector2(x1, y + 1.5), new Vector2(x1, y)) { Layer = layer });
        doc.Entities.Add(new Line(new Vector2(x2, y + 1.5), new Vector2(x2, y)) { Layer = layer });
        doc.Entities.Add(new Line(new Vector2(x1, y), new Vector2(x2, y)) { Layer = layer });
        doc.Entities.Add(new Text(DxfSafe(label), new Vector2((x1 + x2) / 2 - 2, y - 3), 2.0) { Layer = layer });
    }

    // DXF single-line Text is ASCII-friendliest → map the Unicode glyphs we use to DXF/ASCII equivalents.
    // `internal` (not private) so the round-trip test can assert a CEM field reaches the DXF VERBATIM
    // through the same mapping the writer used — asserting the raw CEM string would fail on Ø/µ/² and
    // asserting a hand-copied ASCII form would be a second, drifting definition of this table.
    // 📐 Таблиця ВИМІРЯНА проти `cem/*.json` (2026-08-28), не вгадана: скан усіх маніфестів дав ~35
    // різних не-ASCII гліфів, із яких стара версія мапила СІМ. Решта їхала в DXF як `\U+XXXX`.
    // ⚠️ І це НЕ дефект сам по собі — `\U+XXXX` є штатним DXF-кодуванням Unicode, яке AutoCAD рендерить;
    // тобто мапінг тут про ЧИТАБЕЛЬНІСТЬ у простіших читачах, а не про коректність. Тому додано лише
    // ТЕХНІЧНІ гліфи з однозначним ASCII-еквівалентом (математика, стрілки, § як `sec.`), а кирилиця
    // («Деталь 3») лишається екранованою СВІДОМО: транслітерація власної назви деталі була б втратою
    // сенсу заради косметики, і жодного виміру, що цех бачить її гірше, у нас немає.
    internal static string DxfSafe(string s) => s
        .Replace("Ø", "%%c").Replace("⌀", "%%c").Replace("≈", "~").Replace("≤", "<=").Replace("≥", ">=")
        .Replace("²", "2").Replace("³", "3").Replace("µ", "u").Replace("·", "-").Replace("–", "-").Replace("°", "deg")
        .Replace("—", "-").Replace("−", "-").Replace("×", "x").Replace("§", "sec.")
        .Replace("→", "->").Replace("↔", "<->").Replace("⇒", "=>").Replace("≪", "<<").Replace("≫", ">>")
        .Replace("α", "alpha").Replace("β", "beta").Replace("₂", "2").Replace("₃", "3");
}
