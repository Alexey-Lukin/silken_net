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
// Two outputs from the same CEM: SVG/PDF (human/publication/self-review) + DXF (CAD-native factory
// deliverable, opened in AutoCAD/Fusion — netDxf draws the dimensions). Deterministic, Git-friendly, no
// Library.Go, regenerates on a dim change like metrics.json — the Noyron way (the generator documents
// itself). PoC = Ti-coin (Stage 2, the most urgent physical part, 01_01 §6.1).
internal static class Drawing
{
    private const float Px = 6f;          // scale 6 px/mm (drawing scale 6:1 for a ~Ø16 part)
    private const string Stroke = "#111";
    private const string Dim = "#1166cc";

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
    // Falls back to a minimal material/process line when the CEM carries no notes.
    private static List<string> NotesLines(NotesSpec? n, string? lead = null)
    {
        var lines = new List<string>();
        if (lead is not null) lines.Add(lead);
        if (n is null)
        {
            lines.Add("Material: Ti-6Al-4V (Grade 5). Geometry SSOT = the cem/*.json + STL.");
            return lines;
        }
        void Add(string? label, string? v) { if (!string.IsNullOrWhiteSpace(v)) lines.Add($"{label}: {v}"); }
        Add("Material", n.Material);
        Add("Process", n.Process);
        Add("Surface", n.SurfaceFinish);
        Add("Post-process", n.PostProcess);
        Add("Coating", n.CoatingRestriction);
        Add("Lattice", n.LatticeSpec);
        Add("Inspect", n.Inspection);
        if (n.Extra is { } extra) lines.AddRange(extra);
        return lines;
    }

    // Tolerance-block lines — consume the CEM ToleranceSpec (fits / Lamé-µm / GD&T datums). Null ⇒ empty.
    private static List<string> ToleranceLines(ToleranceSpec? t)
    {
        var lines = new List<string>();
        if (t is null) return lines;
        if (t.Fit is { } fit) lines.Add($"Fit: {fit}");
        if (t.InterferenceMinUm is { } lo && t.InterferenceMaxUm is { } hi) lines.Add($"Interference: {N(lo)}–{N(hi)} µm (Lamé, E_PEEK-aware)");
        if (t.ClearanceMm is { } cl) lines.Add($"Clearance: ≤{N(cl)} mm");
        if (t.Feature is { } f && (t.PlusMm is { } || t.MinusMm is { }))
            lines.Add($"{f}: {N(t.PlusMm ?? 0)}/{N(t.MinusMm ?? 0)} mm");
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

        // TITLE BLOCK (compact canonical fields; the full material/process/notes live in NOTES above)
        TitleBlock(b, 540, 470, new[]
        {
            ("PART", "Ti-coin"),
            ("MATERIAL", "Ti-6Al-4V"),
            ("PROCESS", "SLM/DMLS"),
            ("UNITS / SCALE", "mm / 6:1"),
            ("REV", sha),
            ("SSOT", "cem/ti_coin.json"),
        });

        return Frame(820, 560, b, sha, std);
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
        lines.Add($"SilkenNet Ti-coin | rev {sha} | mm 1:1 | {StandardLabel(std)} | SSOT cem/ti_coin.json");
        double yy = cy - rr - 20;
        foreach (string ln in lines) { doc.Entities.Add(new Text(DxfSafe(ln), new Vector2(cx - rr, yy), 1.6) { Layer = nte }); yy -= 3.2; }

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
    private static string DxfSafe(string s) => s
        .Replace("Ø", "%%c").Replace("⌀", "%%c").Replace("≈", "~").Replace("≤", "<=").Replace("≥", ">=")
        .Replace("²", "2").Replace("³", "3").Replace("µ", "u").Replace("·", "-").Replace("–", "-").Replace("°", "deg");
}
