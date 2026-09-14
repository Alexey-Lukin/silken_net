// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Text.Json;

namespace SilkenCad;

// CEM = Computational Engineering Model manifest: the Git-SSOT input that drives a
// generator. The term + spirit are LEAP 71 Noyron's — a CEM is a DETERMINISTIC
// algorithm, not generative ML. Geometry is COMPUTED from these parameters; the
// .json + the .cs generator together are the source of truth, the STL is a derived
// build artifact (gitignored, parity is on cem/*.metrics.json instead).
internal static class Cem
{
    private static readonly JsonSerializerOptions Opts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    // Cheap discriminator read so `build` can dispatch to the right generator.
    // Which files in a cem/ directory are MANIFESTS. ⛔ The discriminator is the ABSENCE of `kind`,
    // never the filename: siblings live in that directory on purpose (the `*.golden.json` regression
    // baselines sit beside the CEM they pin), and the next one will be named something else.
    // 🔴 Bought 2026-09-12 the expensive way. Seven baselines landed in `cem/`, and FIVE separate globs
    // over that directory silently widened: the ruby provenance report died on a nil sort, `sweep` and
    // the shared test fixture took them as SKUs, and CI went red on the drawing round-trip asserting
    // notes a baseline does not have. I fixed the ruby one and did NOT sweep the class — so the same
    // defect shipped twice in one hour. ⚠️ And the local `dotnet test` that said 131-green ran BEFORE
    // the baselines existed; the commit went out without a re-run.
    public static string[] ManifestFiles(string strDir, string strPattern)
        => [.. Directory.GetFiles(strDir, strPattern)
                        .Where(p => !string.IsNullOrEmpty(SafeKind(p)))
                        .OrderBy(p => p, StringComparer.Ordinal)];

    private static string? SafeKind(string strPath)
    {
        try
        {
            return Kind(File.ReadAllText(strPath));
        }
        catch (Exception)
        {
            return null;   // unreadable / not JSON ⇒ not a manifest, and never a crash in a glob
        }
    }

    public static string Kind(string strJson)
    {
        using JsonDocument doc = JsonDocument.Parse(strJson);
        return doc.RootElement.TryGetProperty("kind", out JsonElement el) && el.GetString() is { } strKind
            ? strKind
            : throw new InvalidDataException("CEM manifest is missing a 'kind' field");
    }

    public static T Parse<T>(string strJson) =>
        JsonSerializer.Deserialize<T>(strJson, Opts)
        ?? throw new InvalidDataException("CEM manifest deserialized to null");
}

// Engineering-drawing PMI (Product Manufacturing Information) — the tolerance + GD&T spec a drawing/DXF
// carries. Per LEAP 71 Noyron, manufacturing constraints live in the CEM (the computational model), NOT
// on a one-off drawing — the `draw` verb just renders them. Optional on every part record (null ⇒ no
// callout). Feeds the factory acceptance contract + the HW.8 / HW.8.9 reconcile.
internal sealed record ToleranceSpec
{
    // Fit / press-fit interference. ⚠ For a Ti shaft in a PEEK bore, `H7/s6` is only the NOMINAL class
    // label — PEEK E≈4 vs Ti≈114 GPa, so the same geometric interference gives a different contact
    // pressure. The REAL band is the Lamé-computed µm (01_01 §4.2, script 50, HW.3.IS), NOT a blind
    // ISO-286 metal-table lookup → put it in InterferenceMin/MaxUm.
    public string? Fit { get; init; }                  // nominal class label, e.g. "H7/s6"
    public float? InterferenceMinUm { get; init; }     // diametral µm; §4.2 wants the Lamé window, zone2_sleeve's is an ISO read (HW.3)
    public float? InterferenceMaxUm { get; init; }
    public float? ClearanceMm { get; init; }           // hex/spline anti-rotation ≤0.05 (01_01 §4.3 C)

    // Linear ± on named features (e.g. "bore_dia", "flange_dia"). A LIST, because a part can carry more
    // than one toleranced size and the single slot this replaced silently capped it at one: the cathode
    // flange spends its slot on `shank_dia` and therefore had no way to give its own PRIMARY DATUM — the
    // machined bus bore — a dimensional row at all (00_07 HW.34). A named feature with NO limits still
    // renders, as loud absence; that is the point, not a gap.
    public IReadOnlyList<LinearToleranceSpec>? Features { get; init; }

    // GD&T datums + geometric tolerances (ISO 1101 — the coaxial stack needs concentricity/runout on the
    // mating bore/flange; the lattice bulk gets no GD&T).
    public string? PrimaryDatum { get; init; }         // e.g. "bore axis"
    public string? SecondaryDatum { get; init; }       // e.g. "flange face"
    public string? ConcentricityMm { get; init; }      // e.g. "0.05"
    public string? RunoutMm { get; init; }
}

// One toleranced linear size. Both limits are optional ON PURPOSE: a feature the shop must hold but
// whose band we have not bought yet prints each missing side as NOT SPECIFIED IN CEM rather than as a
// plausible number — the `?? 0` that once rendered a zero minus-limit (the TIGHTEST possible) is the
// defect this shape exists to prevent.
internal sealed record LinearToleranceSpec
{
    public string? Feature { get; init; }
    public float? PlusMm { get; init; }
    public float? MinusMm { get; init; }
}

// Engineering-drawing notes — the AM-specific acceptance half (material, process, surface finish,
// post-process, coating restrictions, lattice spec, inspection). Plain canon-sourced text the `draw`
// verb lays into the notes block (replaces the hardcoded Ti-coin lines → Noyron-clean). Optional (null
// fields skipped). Canon: 01_01 §1 + 01_02 §1.
internal sealed record NotesSpec
{
    public string? Material { get; init; }             // "Ti-6Al-4V (Grade 5)" | "PEEK 450G"
    public string? Process { get; init; }              // "SLM+HIP" | "CNC (annealed 200–250 °C)" | "EBM"
    public string? SurfaceFinish { get; init; }        // "micro Sa 0.5–5 µm + nano Sv 50–500 nm (EAAE, 01_02 §1.2)"
    public string? PostProcess { get; init; }          // "HIP (01_02 §1.7) · dehydrogenation bake · build tip-down §1.6"
    public string? CoatingRestriction { get; init; }   // "ZnO-Ta/HAp/RGD FORBIDDEN on Zone-1 gyroid (blocks DET) — 01_02 §3.6"
    public string? LatticeSpec { get; init; }          // "porosity 65±2 % / period … / topology … — inspect Archimedes+µCT (ISO/ASTM 52900)"
    public string? Inspection { get; init; }           // "SEM ×500/5000/50000 · ICP-MS Al<1 ppb (01_02 §1.5)"
    public string[]? Extra { get; init; }              // free lines (Ti-coin active-area, RF keep-out, …)
}

// Flat in-vitro Ti coupon (Stage-2 CV/EIS, 01_01 §6.1). Ø16 disc → 1 face ≈ A_electrode 2 cm²
// (01_03 §3.5). Disc not square: RDE-ready, uniform radial j, no corner edge-effects. j is
// normalised on the PROJECTED geometric area (EAAE roughness makes the true area unmeasurable, 01_02 §1.4).
internal sealed record TiCoinCem
{
    public string Kind { get; init; } = "ti_coin";
    public string Name { get; init; } = "ti_coin";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float DiscDiameterMm { get; init; } = 16f;     // 1 face = π·(D/2)² ≈ A_electrode 2 cm² (01_03 §3.5)
    public float DiscThicknessMm { get; init; } = 1f;
    // A lab O-ring / lacquer window can fix exactly 2 cm² INSIDE a larger coupon — decouples A from the coin
    // edge (same A across drop-cast / masked-window / O-ring cell). 0 ⇒ the whole face is the active area.
    public float ActiveWindowDiameterMm { get; init; }
    public float LoopRingRadiusMm { get; init; } = 1.6f;  // torus centreline radius
    public float LoopTubeRadiusMm { get; init; } = 0.6f;  // torus tube (wire) radius
    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (null ⇒ no callout)
    public NotesSpec? Notes { get; init; }                // drawing notes block (null ⇒ defaults)
}

// Zone-1 gyroid anode (01_01 §5): a cartesian-gyroid Ti rod with a central SOLID bus-rod core
// (01_01 §1.4 monolithic; Ø11 founder 2026-06-20, HW.33). v2 = radially GRADED gyroid with three
// INDEPENDENT, CEM-driven axes (the FEA/bio "which is best" answer is open, so none is hard-coded):
//   • pore/cell size — GyroidPeriod{Mm core → RimMm} (biology: ingrowth core / transport rim)
//   • porosity / E   — GyroidWallParam{ core → Rim }  (mechanics: HOLD or GRADE the porosity)
//   • topology       — sheet|network|stepped           (surface vs stress-shielding, HW.33;
//                       sheet|network = RATIFIED 2026-09-10 to network and APPLIED 2026-09-11 — every
//                       shipped anchor manifest now declares it; stepped = zoned-period variant, a
//                       third implemented branch. ⛔ A wallParam never carries across a topology flip:
//                       at the sheet-era 1.0 the network branch lands ~50 % porous, i.e. STIFFER than
//                       the branch it replaced, so re-solve against the porosity target FIRST)
// Core = axis (r=bore/2), Rim = periphery (r=outer/2); an ABSENT *Rim* field ⇒ equals Core ⇒ v1 constant.
// Porosity is MEASURED, never assumed: PorosityTarget is only a verify goal, and 65 % itself is a rough
// placeholder (founder 2026-06-21). ⚠️ The textbook Gibson-Ashby `n=2` for the network branch we ship is
// SUPERSEDED by measurement (2026-09-12): a wall_param sweep fits n = 2.24 on the lattice and 2.27 on the
// shipped annulus, at C ≈ 1 rather than the 0.71 a single density suggested — numbers, the literature
// comparison and the declared ceiling live in 01_01 §5.2 (verb `fea --fit`). Sheet remains the other
// branch (n≈1.3 → higher E), and wood E is anisotropic (HW.33). Porosity is a parameter here, not a
// frozen truth.
internal sealed record AnchorCem
{
    public string Kind { get; init; } = "anchor_zone1";
    public string Name { get; init; } = "anchor_zone1";
    public float VoxelSizeMm { get; init; } = 0.1f;
    public float OuterDiameterMm { get; init; } = 11f;     // founder 2026-06-20 (HW.33)
    public float BusRodDiameterMm { get; init; }           // monolithic SOLID bus rod Ø (01_01 §1.4) = the core of the gyroid annulus; 0 ⇒ no core, the lattice reaches the axis (synthetic in-test coupons only — every shipped SKU declares a rod, pinned by AnchorTests)
    public float LengthMm { get; init; } = 40f;            // Zone-1 30–50 mm

    // Cell-size (pore) axis — period at the core; RimMm tapers it toward the periphery.
    // Core period (mm). ⚠ Printed feature size is TOPOLOGY-dependent and the `0.1·period` that
    // stood here is the SHEET figure: measured 2026-09-12 it is 0.12·period on sheet and
    // 0.36·period on network (01_01 §5.5 — three instruments, ceilings declared there).
    public float GyroidPeriodMm { get; init; } = 2.5f;
    public float GyroidPeriodRimMm { get; init; }          // periphery period (mm); 0 ⇒ = core (constant size)

    // Porosity axis — dimensionless, and its MEANING is topology-dependent, so a value never carries
    // across a topology flip: sheet reads it as a band (solid where |eq| < 0.5·param), network as a LEVEL
    // SHIFT (solid where eq < 0.5·(param−1)). Measured 2026-09-11 on the shipped SKUs: 0.10 ⇒ ~65 %
    // porous on network, while the sheet-era 1.0 ⇒ ~50 %, i.e. STIFFER than the branch it replaced.
    public float GyroidWallParam { get; init; } = 1.0f;    // core band / level
    // Periphery; null (absent) ⇒ = core ⇒ constant porosity. 🔴 NULLABLE, not a `> 0` sentinel, and the
    // reason is the network verdict: on sheet a param ≤ 0 is meaningless (no band), so "0 ⇒ core" cost
    // nothing; on network it is an ORDINARY level and the rim of a porosity gradient legitimately needs
    // it (the shipped graded_porosity rim: −0.46 ⇒ 73 % porous in the rim shell). A sentinel would have collapsed that
    // gradient to constant SILENTLY — the manifest saying one thing and the geometry doing another.
    public float? GyroidWallParamRim { get; init; }

    // sheet (more surface, stiffer) | network (lower-E) | stepped (heterostructure zones: strong pore
    // contrast at constant porosity — uses Period + PeriodRim as the two zone periods, ignores wall-grad)
    // ⚖️ RATIFIED 2026-09-10 (founder, 00_07 HW.33): the anode is NETWORK. This default is NOT that
    // verdict and must not be read as one — it exists for synthetic in-test coupons only. Every shipped
    // cem/anchor_zone1.*.json now DECLARES its topology, pinned by
    // AnchorTests.Every_Shipped_Anchor_Cem_Declares_Its_Topology, so the default is load-bearing for no
    // real part; a new SKU that omits the key reds instead of inheriting a branch nobody chose.
    public string Topology { get; init; } = "sheet";
    // A/B switch for the first-order field normalisation (00_07 HW.49). Default FALSE: every
    // shipped metric was measured on the raw field, so this must never flip by omission.
    public bool NormaliseField { get; init; }
    public float PorosityTarget { get; init; } = 0.65f;    // verify goal only — placeholder, FEA-gated (HW.33)

    // Minimum printable wall of the machine + powder that will print THIS part — a VENDOR INPUT from the
    // DMLS RFQ, not a canon constant (⚖️ founder 2026-09-10, 00_07 HW.33: canon must not hardcode one
    // supplier's machine). null ⇒ the canon default 200 µm (01_01 §5.5) applies, and `verify` says which
    // of the two it used. ⚠️ **This number has TWO roles and the second is the expensive one:** besides
    // being the as-printed threshold, it sets the measurement grid (`step = min(adaptive, floor/4)`), so
    // a vendor floor of 0.1 instead of 0.2 halves the step on every axis — ~8× the cells, roughly an
    // order of magnitude more time per run. Change it knowing you are also changing what a run costs.
    public float? SlmMinWallMm { get; init; }

    // 🔴 This record had NO Notes property until 2026-09-11 (00_07 HW.1), and the absence was SILENT in
    // the worst direction: the deserializer ignores unmapped members, so a `notes` block written into
    // cem/anchor_zone1.*.json would have parsed cleanly and vanished — done-looking and inert. Worse,
    // the comment over NotesSpec.CoatingRestriction illustrates that very field with THIS part's rule
    // ("ZnO-Ta FORBIDDEN on Zone-1 gyroid — blocks DET"), i.e. the field was designed around a part that
    // could not hold it. `draw anchor_zone1` RENDERS them since 2026-09-11, so the pin that every shipped SKU
    // declares its coating restriction is no longer the only thing keeping them load-bearing — it is now what
    // stops a NEW SKU shipping silent on the one restriction whose violation is unrecoverable.
    public NotesSpec? Notes { get; init; }

    // 🔴 The SAME silent-absence class as `Notes` above, one field over, and it survived the 2026-09-11
    // pass because that pass was scoped to notes: this record had no `Tolerances` slot either, so a
    // `tolerances` block written into cem/anchor_zone1.*.json would have parsed cleanly and evaporated
    // (Cem.Parse runs without UnmappedMemberHandling.Disallow — gotcha 0b). Added 2026-09-11 with
    // `draw anchor_zone1` (00_07 HW.1): a drawing is an ACCEPTANCE contract, and a lattice part whose
    // primary mating Ø carries no PMI row at all is the silent half of the loud-absence rule.
    // ⛔ What it must NOT hold: a lattice GD&T profile. Canon 01_02 §6 forbids drawing the gyroid
    // cell-by-cell — over-drawing it promises a precision nobody measures (acceptance is Archimedes +
    // µCT, ISO/ASTM 52900). PMI here is the ENVELOPE only.
    public ToleranceSpec? Tolerances { get; init; }
}

// Mechanical-lock shank (01_01 §4.3 A/B) — the §4.3 BLOCKER-3 lock against PEEK cold-flow creep
// (HW.26): annular ratchet barbs + a DIN-471 retaining groove on the solid Ti shank that press-fits
// into the PEEK sleeve. Zone 1 (real Ø11) is a self-contained demo part — NOT yet integrated into the
// gyroid rod (separate session, 00_07); the Zone-3 set (placeholder Ø) is already the cathode flange's
// shank (`CathodeFlange.ShankCem` → `MechanicalLock.Build`). Canon over-specifies the tooth (h, base,
// α, β all fixed); a triangle has 2 free params, so we keep α/β + h and DERIVE base ≈ 2.1·h — verify
// MEASURES it against §4.3 [0.40,0.60]. Barbs emit GEOMETRY only: the 3–5× pull-out, the PEEK 150 °C
// click and friction retention are FEA (Гусак, HW.3.IS) + bench, never asserted here.
internal sealed record MechanicalLockCem
{
    public string Kind { get; init; } = "mechanical_lock";
    public string Name { get; init; } = "mechanical_lock";
    public float VoxelSizeMm { get; init; } = 0.05f;       // barb-feature floor (h≈0.28 → ~6 voxels); exact tip = measured on the part (01_01 §4.3)
    public float ShankDiameterMm { get; init; } = 11f;     // Zone-1 anode Ø (founder, HW.33); Zone-3 = PLACEHOLDER (HW.8 dim-freeze)
    public float ShankLengthMm { get; init; } = 18f;
    public float BoreDiameterMm { get; init; } = 1.35f;    // 0 ⇒ SOLID shank (monolithic anode, the bus IS the metal core, 01_01 §1.4); >0 ⇒ the cathode channel the bus rod threads (Ø1.35 since the clearance verdict, 00_07 HW.34)
    public float ContactStartMm { get; init; } = 2f;       // z where PEEK contact begins
    public float ContactLengthMm { get; init; } = 12f;     // contact zone 8–15 mm (§4.3 A)

    // Ratchet tooth — keep α/β + h, base is DERIVED = h·(cot α + cot β); MEASURED in verify.
    public int BarbRows { get; init; } = 4;                // 3–5 rows (§4.3 A)
    public float BarbHeightMm { get; init; } = 0.28f;      // h 0.25–0.40; base≈0.59 ∈ [0.40,0.60] at α30/β70
    public float LeadAngleDeg { get; init; } = 30f;        // α leading — shallow ⇒ long ramp ⇒ easy hot insert
    public float TrailAngleDeg { get; init; } = 70f;       // β trailing — steep ⇒ short ramp ⇒ hard pull-out
    // ⛔ No direction knob. In the LOCK's own frame — the standalone lock and the flange shank, where z = 0
    //    is the end that enters the PEEK first — the shallow α ramp ALWAYS faces z = 0, because that is what
    //    01_01 §4.3 A's "easy in, hard out" means. The §4.3 figure's "opposite lean" on Zone 3 is the
    //    ASSEMBLED view of two parts pressed in from opposite ends. A ±1 knob that meant the world view to its
    //    author and the local frame to this code shipped the cathode flange as a reversed ratchet (00_07
    //    HW.26): steep face first into the PEEK, shallow ramp against pull-out. A body whose own frame runs
    //    the other way — the Zone-1 anode, where z = 0 is the tree side — must PLACE an integrated shank by
    //    rotating it, never by a sign.

    // DIN-471 retaining-ring groove (§4.3 B) — 1.1 × 0.25 deep for the Ø11 shank, near the outer (capsule-side) end.
    public float GrooveOffsetMm { get; init; } = 15f;
    public float GrooveWidthMm { get; init; } = 1.1f;   // DIN-471 для Ø11 shank (§4.3 B; «0.8×0.6» = off-spec, не штатне кільце)
    public float GrooveDepthMm { get; init; } = 0.25f;

    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (null ⇒ no callout — no DIN-471 band cited without a source)
    public NotesSpec? Notes { get; init; }                // drawing notes block (null ⇒ NOT SPECIFIED IN CEM per field)
}

// The ONE O-ring face seal between the flange top face and the radome rim (02_02 §3.2 / §3.5; ⚖️ 2026-09-10,
// 00_07 HW.33 branch (а), APPLIED 2026-09-14). Carried on BOTH parts and pinned equal by xUnit (as the lug
// radius is): the flange cuts its groove from it, the radome sizes its seal land from it. Depth and width are
// DERIVED here and stored nowhere, so the gland cannot drift from its inputs.
// 🔗 C#↔Python crossing, EXPLICIT: the same formula is `gland_verdict` in
//    tools/in_silico/scripts/52_z_stack_tolerance.py, which READS these fields off the manifests at runtime and
//    refuses to run if they differ from its own constants; RadomeTests pins the derived values here against that
//    script's cache (`cache/mechanical/z_stack_tolerance.json` §gland_geometry / §applied_gland) — both directions.
internal sealed record ORingGlandCem
{
    public float CsMm { get; init; } = 1.78f;           // cord section, AS568 W .070" (02_02 §3.2)
    // Ratified nominal squeeze (⚖️ 2026-09-10): the centre of the 19–30 % intersection of industry practice
    // (15–30 %) and the Parker face-seal window (19–32 %), 02_02 §3.5. A FRACTION, not a percent.
    public float Squeeze { get; init; } = 0.245f;
    // Gland fill ceiling = ring section / groove section. ⚖️ OPEN (00_07 HW.33): designed to 80 % — the
    // industry rule script 52 cites (a groove ~25 % larger than the ring) — until the verdict; raising it to
    // 85 / 90 % is the cheapest lever on the rim-cavity ceiling (+0.27 / +0.52 mm Ø) and is NOT taken here.
    public float GlandFill { get; init; } = 0.80f;

    public float DepthMm => CsMm * (1f - Squeeze);                    // 1.344 at 24.5 %
    public float RingAreaMm2 => MathF.PI / 4f * CsMm * CsMm;           // the section the ring displaces (2.489)
    public float WidthMm => RingAreaMm2 / (GlandFill * DepthMm);        // 2.315 at 80 % fill
}

// Zone 3 cathode flange (Деталь 3, 01_01 §1 + 02_02 §1.2) — the capsule-side anchor end: a SOLID Ti
// flange (Ø25 frozen) on a barbed shank that press-fits into the PEEK Zone-2 sleeve. Top face = pogo-pad
// plane (centre GND bus + outer V+, Hard Gold — coating, NOT geometry); the side/perimeter is the cathode
// catalytic zone (Laccase/ZIF + PTFE-GDL, O₂ from the side under the radome bell — 02_02 §1.2, фаза-2).
// Bayonet lugs mate the PEEK Radome (Деталь 4). Barbs reuse the §4.3 lock (Zone-3 set, same local profile).
// Shank Ø + flange thickness = HW.8 placeholders (no-premature-canon).
internal sealed record CathodeFlangeCem
{
    public string Kind { get; init; } = "cathode_flange";
    public string Name { get; init; } = "cathode_flange";
    public float VoxelSizeMm { get; init; } = 0.05f;       // barb-feature floor (as mechanical_lock)
    public float FlangeDiameterMm { get; init; } = 25f;    // frozen (01_01 §1 = Radome Ø, 02_02 §1.3)
    public float FlangeThicknessMm { get; init; } = 3f;    // placeholder (HW.8 dim-freeze)
    public float ShankDiameterMm { get; init; } = 9f;      // placeholder (HW.8); Zone-3 into PEEK
    public float ShankLengthMm { get; init; } = 14f;
    public float BoreDiameterMm { get; init; } = 1.35f;    // GND bus channel (hollow through flange+shank) — the monolithic rod threads it, isolated. This DEFAULT is the effective channel for the F3 gate on the full stack, because the assembly manifests declare no such field (00_07 HW.45) — so it moves with canon 01_01 §1.4, not behind it
    public float BusLinerThicknessMm { get; init; }        // bus-rod insulation liner in the channel (01_01 §1.4); feeds the F3 BusRodClears clearance
    // How far the liner reaches BELOW the shank face, into the PEEK gap (01_01 §1.4, ⚖️ 2026-09-12).
    // ⛔ Not decoration and not a safety margin: the rod+tube pair takes up its radial play before it
    // reaches the bore, so flush with the mouth the bore EDGE meets the tube's END FACE (ring on ring)
    // instead of its flank. Derived in 55_bus_mechanical (§clearance_regime.edge_bearing.liner_start — the
    // value lives in that cache, on the bonded member), ratified at ≥ 1.0. The MATERIALS do not depend on it — the play is channel-side either way — the FEATURE does.
    public float BusLinerProtrusionMm { get; init; }       // liner overhang below the shank face (mm)

    // Barbs (§4.3, reuse MechanicalLock; the shallow ramp faces the shank tip that enters the PEEK first)
    public int BarbRows { get; init; } = 3;
    public float BarbHeightMm { get; init; } = 0.28f;
    public float LeadAngleDeg { get; init; } = 30f;
    public float TrailAngleDeg { get; init; } = 70f;
    public float ContactStartMm { get; init; } = 2f;
    public float ContactLengthMm { get; init; } = 9f;
    public float GrooveOffsetMm { get; init; } = 12f;      // groove z (our choice); the groove = the DIN 471 row for Ø9
    public float GrooveWidthMm { get; init; } = 1.1f;      // DIN 471 d1 = 9: m 1.1 (1.0 is the RING thickness s, not the groove)
    public float GrooveDepthMm { get; init; } = 0.2f;      // d2 8.6 ⇒ depth 0.2

    // Bayonet lugs (mate the Радом socket, фаза 2) — radial pins evenly spaced
    public int BayonetLugs { get; init; } = 3;
    public float LugProtrusionMm { get; init; } = 2f;      // radial protrusion beyond the flange rim
    public float LugRadiusMm { get; init; } = 1.5f;        // pin radius
    // Socket running clearance over the lug — the RADOME's socket field, mirrored here because the groove
    // below is positioned off the socket band (`lug radius + slot clearance`) and keeps one slot clearance of
    // seal land on each side, i.e. off the radome's radial layout (Radome.SealLand*). Pinned equal to
    // RadomeCem.SlotClearanceMm by xUnit, as the lug radius already is. No canon ground (00_07 HW.48 → HW.33).
    public float SlotClearanceMm { get; init; } = 0.3f;

    // The ONE O-ring groove (⚖️ 2026-09-10, applied 2026-09-14, 00_07 HW.33 branch (а)): a face-seal groove on
    // the flange TOP (capsule-side) face, closed by the FLAT rim of the radome's seal land. NOT the underside:
    // there is no elastomer under the flange. Depth and width are DERIVED from this spec
    // (CathodeFlange.ORingGroove*) — depth = CS·(1 − squeeze) = 1.344, width = ring area / (fill · depth) = 2.315
    // at the 80 % fill the open ⚖️ designs to — and so is the radial position (inside the radome's seal land,
    // one slot clearance of land each side). Nothing about the groove is stored, so nothing can go stale.
    // 🔑 With the rim as a HARD DATUM on this face the squeeze is set by this depth ALONE — the bayonet no
    //    longer sets Z for the seal — which is why script 52's O-ring chain is ONE machined dimension now.
    public ORingGlandCem ORing { get; init; } = new();

    // Pogo-pad features (02_02 §1.2) — the central GND bus pad (Hard Gold ENIG = the Ti↔Au galvanic-trap
    // fix) + the PEEK isolation ring guarding the centre↔outer short. Ø = HW.8 placeholders (canon says
    // «точні Ø фланця/площадки потребують CAD → HW.8»; the flange drawing is that forcing function, §F).
    public float CentralPadDiameterMm { get; init; } = 4.5f;   // GND bus-exit pad, Hard Gold ENIG (4–5, HW.8)
    public float IsolationRingWidthMm { get; init; } = 1.5f;   // PEEK ring centre↔outer (≥1.5, short-circuit guard) — a
                                                               // DRAWING annotation of a requirement: CathodeFlange.cs does not
                                                               // model the ring (solid Ti top face; open, 00_07 HW.34)

    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (concentricity — coaxial stack)
    public NotesSpec? Notes { get; init; }                // drawing notes block
}

// PEEK Radome (Деталь 4, 02_01 §5.2 + 01_04 §5.5) — the radio-transparent dome that bayonets onto the
// Zone-3 cathode flange (Деталь 3) and caps the PCB. A HOLLOW PEEK shell (Ø25): a rounded shield bell
// (≥3 mm over bark, R≥5 — anti-overgrowth, no callus-grip edge; ⛔ neither field DRIVES the geometry —
// the cap rise and edge radius are both the dome radius, and these two are floor-checks only) + an
// internal PCB cavity (⛔ cavity height ≠ antenna↔Ti clearance — 00_07 HW.33) + a LOCAL INTERNAL RIM BOSS whose
// outer band carries the bayonet socket (L-slot mating the Деталь-3 lugs) and whose inner band is the seal land
// that closes the flange's single O-ring groove — the rim itself is FLAT (Radome.cs). The cathode is NOT
// sealed under the dome — it breathes O₂ from the SIDE/perimeter (02_02 §1.2; gas-phase 5–10× vs dissolved).
internal sealed record RadomeCem
{
    public string Kind { get; init; } = "radome";
    public string Name { get; init; } = "radome";
    public float VoxelSizeMm { get; init; } = 0.1f;        // dome ~Ø25, no sub-mm features → 0.1 ok
    public float DomeDiameterMm { get; init; } = 25f;      // frozen (= Zone-3 flange Ø, 02_02 §1.3)
    public float WallThicknessMm { get; init; } = 2f;      // 1.5–2.0 (RF vs strength, 02_01 §5.2)
    public float CavityHeightMm { get; init; } = 13f;      // PCB stack (Power+B2B+RF). ⛔ NOT antenna↔Ti: that is cavityH − lockGrooveZ − t/2 = 8.0 here, and the ≥12 floor is OURS (canon asks ≥8) — 00_07 HW.33
    public float BellRiseMm { get; init; } = 3f;           // rounded top over the body (≥3, 01_04 §5.5)
    public float BellRadiusMm { get; init; } = 5f;         // top edge round (≥5 — no callus-grip edge)

    // Bayonet socket (mate Деталь-3 lugs) — L-slot: 3 axial entry slots + a circumferential lock groove
    public int BayonetLugs { get; init; } = 3;
    public float LugRadiusMm { get; init; } = 1.5f;        // = Деталь-3 lug radius (mate-fit)
    public float SlotClearanceMm { get; init; } = 0.3f;    // socket slot clearance over the lug
    public float LockGrooveZMm { get; init; } = 3.5f;      // z of the circumferential lock groove from the rim

    // The seal this rim closes (⚖️ 2026-09-10, applied 2026-09-14, 00_07 HW.33): the O-ring sits in the FLANGE's
    // groove and this rim is FLAT — the counter-groove that used to be cut here is gone, not shallower. The spec
    // is carried on both parts (pinned equal by xUnit, like the lug radius) because the radome's SEAL LAND width is
    // derived from it: seal band = gland width + 2·slot clearance, and the local internal rim boss that carries it
    // (Radome.Boss*) is what narrows the rim cavity to the ≤ Ø15.57 ceiling handed to the board layout (HW.9).
    public ORingGlandCem ORing { get; init; } = new();

    // Added 2026-09-11 with AnchorCem's (00_07 HW.1) — same silent absence: unmapped members are dropped,
    // so a `notes` block here would have parsed and disappeared. `draw radome` does not exist yet.
    public NotesSpec? Notes { get; init; }
}

// Zone 2 PEEK thermal-break sleeve (Деталь 2, 01_01 §1 + §4.1/§4.2) — the MIDDLE part: a plain hollow
// PEEK tube that press-fits onto the Zone-1 anode shaft (one end) and receives the Zone-3 flange shank
// (the other end), thermally decoupling the buried anode from the capsule-side cathode. Frozen dims
// (01_01 §1): bore Ø11 (= Zone-1 shaft, press-fit H7/s6), wall 2.0 mm (robust default, NOT CTE-limited —
// unified Lamé §4.2: combined SF 5.6× / thermal-only 14.6× / press-fit-only 9×), OD Ø15 = the WOUND in
// the tree (CODIT <25 → DBH ≥38). Length 50 mm (axial
// thermal break, §4.1). The bore is a plain round hole: anti-rotation is a hex/spline profile in canon
// (§1 + §4.3 C, ≤0.05 mm clearance) but that is bench-gated and not needed for the mate-audit → deferred
// (00_07). DIN-471 retaining grooves live on the Ti Zone-1/Zone-3 ends (§3 step 6), NOT the PEEK sleeve;
// barbs are pressed INTO the bore by the Ti shanks at 150 °C (§3 steps 4–5) → the PEEK bore is smooth
// here. The monolithic bus rod (01_01 §1.4) is the ANODE's own solid core, not in the sleeve (the sleeve bore Ø11 holds the Ti shaft).
internal sealed record Zone2SleeveCem
{
    public string Kind { get; init; } = "zone2_sleeve";
    public string Name { get; init; } = "zone2_sleeve";
    public float VoxelSizeMm { get; init; } = 0.1f;       // no sub-mm features (a plain tube) → 0.1 ok (as radome)
    public float BoreDiameterMm { get; init; } = 11f;     // = Zone-1 anode Ø (press-fit), frozen 01_01 §1
    public float WallThicknessMm { get; init; } = 2f;     // frozen §1 — robust default, NOT CTE-limited (§4.2)
    public float LengthMm { get; init; } = 50f;           // axial thermal break (§4.1), frozen
    // OD = bore + 2·wall = Ø15 = the wound diameter in the tree (derived in Zone2Sleeve.OuterR, not stored).
    public ToleranceSpec? Tolerances { get; init; }       // drawing PMI (press-fit µm band — an ISO 286 read today; the Lamé window is open, 00_07 HW.3 · hex clearance)
    public NotesSpec? Notes { get; init; }                // drawing notes block
}

// Capsule-end anchor ASSEMBLY (Деталь 3 ↔ Деталь 4, 02_02 §4 — Механізм Фіксації Капсули). The first
// INTEGRATION artifact: the per-part generators are each verified in isolation, but nothing yet proves
// they MATE. This CEM drives `Assembly` to bring the cathode flange and the PEEK radome into one
// coordinate frame at the bayonet-closed datum (radome lock-groove aligned to the flange lugs) and
// MEASURE the residual mismatch — a failed verify with concrete numbers is the valuable result (HW.17).
// Reuses the Деталь-3 / Деталь-4 records wholesale (nested), so the assembly inherits their frozen dims
// and a CEM may override a sub-field or keep the defaults. Z-stack inputs come from the in-silico
// 1-D tolerance chain (`tools/in_silico/scripts/52_z_stack_tolerance.py`) — the geometry mirror of it.
internal sealed record AnchorAssemblyCem
{
    public string Kind { get; init; } = "anchor_assembly";
    public string Name { get; init; } = "anchor_assembly";
    public float VoxelSizeMm { get; init; } = 0.15f;   // assembly-scale (Ø~30 × ~38 mm) — disc/wall/lug interference, not barbs

    // MATE-Ø candidate (HW.17): asis = baseline (surfaces the conflict) · skirt = radome enclosing skirt to
    // Ø(lug-tip + clearance) · inboard = flange lugs kept within Ø25 (protrusion clamped). asis is the audit.
    public string MateStrategy { get; init; } = "asis";

    // Z-stack input (script 52): the RF antenna↔Ti floor (02_01 §5.3). ⛔ The O-ring rim↔Zone-3 gap that used
    // to sit beside it (`o_ring_gap_mm` 1.424 = CS·(1 − 0.20), a script-52 mirror) is GONE, not zeroed: under
    // branch (а) (⚖️ 2026-09-10, applied 2026-09-14) the radome rim is a HARD DATUM on the flange top face and
    // the squeeze is the flange groove's own derived depth (CathodeFlangeCem.ORing), so a face gap is not a
    // parameter of the mate any more — Assembly.BayonetZMismatchMm / RequiredLugZMm carry no gap term.
    // ⛔ This 12 is OUR number, not canon's — do NOT "correct" a measured 8.0 upward to meet it.
    // 02_01 §5.3's normative table asks for ≥ 8 mm (10-15 desirable), grounds it on λ/40 = 8.6, and
    // makes HFSS mandatory below 10. Its only 12 is the OUTCOME of a proposed two-deck board stack
    // (standoff 8-10 over a Power Deck sitting ~2 over the flange), i.e. a design point mirrored here
    // as if it were a floor. Same mirror in 52_z_stack_tolerance.RF_ANT_TI_CLEARANCE_MIN.
    // Which number is the acceptance floor is an open verdict (00_07 HW.33); the measurement that
    // settles it is the UNI.10 VNA sweep of Z-clearance 5/8/12. [2026-09-11]
    public float RfClearanceMinMm { get; init; } = 12f;   // antenna↔Ti min Z for VSWR (02_01 §5.3 — read the ⛔ above)
    public float SkirtClearanceMm { get; init; } = 0.5f;  // skirt OD = lug-tip Ø + 2·clearance

    // Components — reuse the per-part records (nested); defaults = the frozen Деталь-3 / Деталь-4 dims.
    public CathodeFlangeCem Flange { get; init; } = new();
    public RadomeCem Radome { get; init; } = new();
}

// Full anchor AXIAL stack (Zone 1 anode → Zone 2 PEEK sleeve → Zone 3 flange → Zone 4 radome, 01_01
// §1 + §3). The SECOND integration artifact (after the capsule-end Assembly): it brings the WHOLE
// anchor into one frame along its axis and MEASURES the PRESS-FIT interfaces no prior part ever proved
// mate — Zone-1↔Zone-2 and Zone-2↔Zone-3. Like Assembly it is an AUDIT table, not a part pass/fail:
// the press-fit findings are the real un-reconciled state (HW.8), surfaced as ⚠ + asserted by the pure
// xUnit suite. Reuses the per-part records wholesale (nested) — Zone1 (AnchorCem) + Zone2 (Zone2SleeveCem)
// + the existing capsule-end Assembly (AnchorAssemblyCem = flange+radome) — so it inherits every frozen
// dim and the bayonet (Zone-3↔Zone-4) audit comes for free. Render uses the Zone-1 ENVELOPE (a solid
// Ø11 rod), not the gyroid: a press-fit cares about the OD, not the internal porosity (that lives in
// anchor_zone1 @0.1) — and it keeps the stack-scale 0.2 mm voxel safe (a ~0.25 mm gyroid wall would
// fragment at 0.2). Z-datum = tree-side at z=0 (anode bottom) → capsule-side up.
internal sealed record AnchorAxialStackCem
{
    public string Kind { get; init; } = "anchor_axial_stack";
    public string Name { get; init; } = "anchor_axial_stack";
    public float VoxelSizeMm { get; init; } = 0.2f;     // stack-scale (Ø15 × ~100 mm) — measures fit/interference, not porosity

    // How deep the Zone-1 anode shaft inserts into the Zone-2 bore (press-fit overlap). The Zone-3 shank
    // enters the OTHER end by its own shank length → InsertionBudget guards the two shanks don't collide.
    // 30 is an HW.8 PLACEHOLDER, not a frozen dim (F2 budget 50−30−14 = 6 mm) — and the in-silico half
    // re-types the same value under TWO names, `L_A_INSERT` and `Z1_INSERTION_MM`: grep both and follow
    // their importers. No gate binds the two halves, so a change here is swept BY VALUE.
    // ⚠️ `verify` judges it against the window of the Zone-1 lock this stack names below and flags it when
    // outside (AxialStack.Zone1InsertionConflict; the standing conflict is 00_07 HW.26 G1) — a detector,
    // never a correction.
    public float Zone1InsertionMm { get; init; } = 30f;

    // The Zone-1 lock that insertion is judged against — a FILENAME beside this manifest, never a copy of
    // its numbers: the barb/groove geometry has one home, the lock manifest, and a nested MechanicalLockCem
    // would fill every absent field from record defaults (gotcha #0a) — whose contact zone and groove ARE
    // the Zone-1 lock's, so a wrong or empty copy would still print the right window. null ⇒ the window
    // prints as NOT SPECIFIED IN CEM. Resolved by AxialStack.Zone1Lock (00_07 HW.26).
    public string? Zone1LockManifest { get; init; }

    // Components — reuse the per-part records (nested); defaults = the frozen Zone-1 / Zone-2 dims + the
    // capsule-end (flange + radome) sub-assembly (it carries its own mate strategy).
    public AnchorCem Zone1 { get; init; } = new();
    public Zone2SleeveCem Zone2 { get; init; } = new();
    public AnchorAssemblyCem Capsule { get; init; } = new();
}
