using System.Globalization;
using System.Text;

namespace SilkenCad;

// CEM-native engineering drawing (research → tools/cad/docs/drawings_program.md). A drawing is just
// orthographic views + dimensions + a title block — all computed ANALYTICALLY from the CEM numbers we
// already own (NOT from the lossy voxel mesh; STL→STEP→drawing loses precision + needs manual rebuild).
// Pure string-built SVG: deterministic, Git-friendly, no Library.Go, regenerates on a dim change like
// metrics.json — the Noyron way (the generator documents itself). PoC = Ti-coin (Stage 2, the most
// urgent physical part, 01_01 §6.1); simple anchor parts follow the same primitives. First-angle / ISO.
internal static class Drawing
{
    private const float Px = 6f;          // scale 6 px/mm (drawing scale 6:1 for a ~Ø16 part)
    private const string Stroke = "#111";
    private const string Dim = "#1166cc";
    private const string Hidden = "#999";

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

    private static string Frame(double w, double h, StringBuilder body, string sha)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"<svg xmlns='http://www.w3.org/2000/svg' width='{N(w)}' height='{N(h)}' viewBox='0 0 {N(w)} {N(h)}'>");
        sb.AppendLine($"<rect x='0' y='0' width='{N(w)}' height='{N(h)}' fill='white'/>");
        sb.AppendLine(Rect(8, 8, w - 16, h - 16, Stroke, 1.2));            // drawing border
        sb.Append(body);
        sb.AppendLine(Text(w - 14, h - 14, $"SilkenNet · CEM-native drawing · rev {sha} · units mm · scale 6:1 · first-angle (ISO)", 8, "end", "#888"));
        sb.AppendLine("</svg>");
        return sb.ToString();
    }

    // ── Ti-coin (Stage-2 coupon, 01_01 §6.1) — front (Ø disc) + side (thickness) + eyelet + A_electrode ──
    public static string TiCoin(TiCoinCem cem, string sha)
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

        // NOTES block (AM-specific acceptance contract — drawings_program.md §6)
        double a = Math.PI * Math.Pow(winMm / 2.0, 2) / 100.0;
        double ny = 300;
        b.AppendLine(Text(20, ny, "NOTES:", 10, "start", Stroke, "bold"));
        string[] notes =
        {
            $"1. Material: Ti-6Al-4V (Grade 5), SLM/DMLS.",
            $"2. Active electrode area ≈ {N(a)} cm² (1 face; j = I/A projected, 01_03 §3.5).",
            cem.ActiveWindowDiameterMm > 0f
                ? $"   Defined-area window Ø{N(cem.ActiveWindowDiameterMm)} (dashed) — O-ring / lacquer cell."
                : "   Whole face is the active area (no defined window).",
            "3. Post-process: EAAE + dehydrogenation bake 250°C (01_02 §1.3, HW.27);",
            "   selective Hard-Gold ENIG on the clip tab only (02_02 §1.2) — mask the rest.",
            "4. Surface: dual-scale roughness Sa (01_02 §1.2). No HIP needed (coupon).",
            "5. Eyelet = potentiostat-clip feature; keep clear of the active face.",
            "6. Geometry SSOT = cem/ti_coin.json + STL; inspect Ø/area by optical scan.",
        };
        for (int i = 0; i < notes.Length; i++) b.AppendLine(Text(20, ny + 16 + (i * 14), notes[i], 9, "start", "#333"));

        // TITLE BLOCK
        TitleBlock(b, 540, 470, new[]
        {
            ("PART", "Ti-coin"),
            ("MATERIAL", "Ti-6Al-4V"),
            ("PROCESS", "SLM/DMLS"),
            ("UNITS / SCALE", "mm / 6:1"),
            ("REV", sha),
            ("SSOT", "cem/ti_coin.json"),
        });

        return Frame(820, 560, b, sha);
    }
}
