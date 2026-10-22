#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Cell-shape cache ↔ canon drift guard (00_07 HW.33). HARD gate, wired into docs.yml.
# Pure Ruby stdlib (json) — no .NET, no conda → CI-safe.
#
# 🔴 WHY IT EXISTS. The `cellshape` measurement landed in `01_01 §5.5` on 2026-10-22 and an adversary's
# first question was the right one: nothing tied those numbers to the caches they came from. The sibling
# guards cannot: `fea_canon_sync` reads `tools/cad/cache/fea` and `test_doc_cache_sync.py` hard-codes
# `tools/in_silico/cache`, so `tools/cad/cache/topology` had no reader at all. The numbers canon quotes are
# RANGES OVER SKUs — exactly the arithmetic-about-a-cache class a comparison holds and prose cannot, and the
# class that had already produced two wrong figures the day the FE numbers landed.
#
# WHAT IT CHECKS — the layers below, in increasing distance from the raw data. ⛔ No count here: a header that
# counts its own file lies on the next edit (the lesson `fea_canon_sync`'s header paid for twice).
#   1. PROVENANCE — every shipped `anchor_zone1.*` manifest has a committed cache, measured with the settings
#      canon's sentence names, carrying the variants that SKU must have.
#   2. TRANSCRIPTION — each range canon states, against the min/max over the committed caches: the top-outer
#      stretches, the degree of anisotropy and its tilt, the chord ratios, specific surface, the print-floor
#      shares, the two alternatives' figures, the controls, and the two axial-period runs.
#   3. DERIVATION — the figures canon computes from the MANIFESTS rather than from a cache: the axial shear at
#      the rim corner, γ = (L/R)·(P_core/P_rim − 1), the in-plane term ε at the outer third, and the
#      irreducible in-plane anisotropy P_core/P_rim.
#
# ⚠️ DECLARED CEILING:
#   • It judges NUMBERS, never the reasoning around them. A range can match under a sentence that misdescribes
#     what was measured — which is why the ⛔ lines in §5.5 (det J does not explain porosity; the pure-shear
#     formula is not the stretch) are held by the prose and by `CellShape.cs`, not by this gate.
#   • 🔴 It CANNOT see the instrument-floor figures canon quotes (~8 % at 400 centres · ~5 % at 1500 · ≤ ~1.3 %
#     at 6000 or on a long probe · the cubic term's ≤ ~1.5 %) or the probe-length study (13.7 % → 8.8 % → 2.7 %):
#     those come from `CellShapeTests`' analytic pin and from an adversary's independent replica, not from any
#     committed cache. Their carrier is the test and the `CellShape.cs` header. Same for the core-third
#     «12–18 % before the cap» figure: the pre-cap run is deliberately NOT committed.
#   • It does not re-run the instrument — `CellShapeTests.Every_Committed_Cellshape_Cache_Was_Measured_By_Todays_Instrument`
#     is the half that does, and it is the gate that reddens when the code moves under a stale cache.
#   • A range is checked as a RANGE: canon rounds to the digits it prints, so a cache change inside the printed
#     rounding does not red. That is deliberate — the alternative is canon quoting five decimals.

require "json"

ROOT = File.expand_path("..", __dir__)
CANON = File.join(ROOT, "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md")
TRACKER = File.join(ROOT, "docs/00_07_Action_Plan_Tracker.md")
CEM_DIR = File.join(ROOT, "tools/cad/cem")
CACHE_DIR = File.join(ROOT, "tools/cad/cache/topology")

failures = []
canon = File.read(CANON)
TRACKER_TEXT = File.read(TRACKER)

manifests = Dir[File.join(CEM_DIR, "anchor_zone1.*.json")].reject { |p| p.include?(".golden.") }.sort
failures << "no anchor_zone1 manifests found — the gate would be vacuous" if manifests.empty?

caches = {}
manifests.each do |path|
  cem = JSON.parse(File.read(path))
  name = cem["name"]
  cache_path = File.join(CACHE_DIR, "cellshape.#{name}.json")
  unless File.exist?(cache_path)
    failures << "#{name}: no committed cellshape cache — run `cellshape cem/#{File.basename(path)}` (00_07 HW.33)"
    next
  end
  caches[name] = { cem: cem, cache: JSON.parse(File.read(cache_path)) }
end

# ── 1. PROVENANCE ────────────────────────────────────────────────────────────────────────────────
# A period-graded SKU must carry all three variants (the verdict's closed list is read off them); a
# period-CONSTANT one must carry only `as_built` — a third variant there would be a copy of the first.
caches.each do |name, h|
  cache = h[:cache]
  graded = cache["period_rim_mm"] != cache["period_core_mm"] && cache["topology"] != "stepped"
  want = graded ? %w[as_built z_origin_mid in_plane_only] : %w[as_built]
  got = cache["variants"].map { |v| v["variant"] }
  failures << "#{name}: cache carries variants #{got.inspect}, expected #{want.inspect}" if got != want
  failures << "#{name}: cache topology #{cache['topology']} ≠ manifest #{h[:cem]['topology']}" if cache["topology"] != h[:cem]["topology"]
end

# Each variant's SUMMARY fields must be the rows' own extrema — the transcription layer reads the ROWS, so a
# summary field left behind by a hand edit or a half-finished run would otherwise sit there uncontradicted
# (measured: mutating `max_degree_of_anisotropy` alone kept this gate green until this check existed).
caches.each do |name, h|
  h[:cache]["variants"].each do |v|
    { "max_degree_of_anisotropy" => v["rows"].map { |r| r["degree_of_anisotropy"] }.max,
      "min_stretch" => v["rows"].map { |r| r["stretch_measured"][0] }.min,
      "max_sub_floor_solid_fraction_by_cell" => v["rows"].map { |r| r["sub_floor_solid_fraction"] }.max }
      .each do |key, want|
        next if (v[key] - want).abs <= 1e-12

        failures << "#{name} [#{v['variant']}]: #{key} says #{v[key]}, its own rows give #{want} — " \
                    "the cache was edited by hand or written by a half-finished run"
      end
  end
end

# The settings canon's sentence names: the top bin is 4.75–5.25 mm and the outer shell is the outer THIRD.
graded = caches.select { |_, h| h[:cache]["period_rim_mm"] != h[:cache]["period_core_mm"] && h[:cache]["topology"] != "stepped" }
failures << "fewer than five period-graded SKUs are cached — canon's ranges are stated over five" if graded.size < 5

def outer_rows(variant, shells = nil)
  shells ||= variant["rows"].map { |r| r["shell"] }.max
  variant["rows"].select { |r| r["shell"] == shells }.sort_by { |r| r["z_lo_mm"] }
end

bin_mm = graded.map { |_, h| outer_rows(h[:cache]["variants"][0]).last.then { |r| r["z_hi_mm"] - r["z_lo_mm"] } }
if bin_mm.any?
  lo, hi = bin_mm.minmax
  if (lo - 4.75).abs > 5e-3 || (hi - 5.25).abs > 5e-3
    failures << "canon says the top bin is 4.75–5.25 mm; the caches give #{format('%.2f', lo)}–#{format('%.2f', hi)}"
  end
end

# ── 2. TRANSCRIPTION — each range canon prints, against the caches ───────────────────────────────
# An anchor is a REGEX naming the sentence's shape plus the values that shape must carry. A vanished
# anchor fails loudly: the sentence is the carrier, so rewording it means re-deriving it here, never
# dropping the check (the rule `fea_canon_sync` learned — a silent anchor is a silent gate).
anchors_seen = 0
def anchor(failures, canon, label, re, values, digits)
  m = canon.match(re)
  if m.nil?
    failures << "the «#{label}» sentence is gone or reworded — fix its shape here, do not drop the check"
    return 0
  end
  m.captures.zip(values).each_with_index do |(quoted, value), i|
    rendered = format("%.#{digits}f", value)
    failures << "#{label} [#{i}]: canon says #{quoted}, the caches give #{rendered}" if rendered != quoted
  end
  1
end

if graded.size >= 5
  tops = graded.map { |_, h| outer_rows(h[:cache]["variants"][0]).last }
  bots = graded.map { |_, h| outer_rows(h[:cache]["variants"][0]).first }
  vars = ->(i) { graded.map { |_, h| h[:cache]["variants"][i] } }

  lam_min = tops.map { |r| r["stretch_measured"][0] }.minmax
  lam_max = tops.map { |r| r["stretch_measured"][2] }.minmax
  da = tops.map { |r| r["degree_of_anisotropy"] }.minmax
  tilt = tops.map { |r| r["compressed_axis_tilt_from_z_deg"] }.minmax
  chord_solid = tops.map { |r| r["solid_chord_compressed_mm"] / r["nominal_solid_chord_mm"] }.minmax
  chord_pore = tops.map { |r| r["pore_chord_compressed_mm"] / r["nominal_pore_chord_mm"] }.minmax
  chord_long = tops.map { |r| r["solid_chord_elongated_mm"] / r["nominal_solid_chord_mm"] }.minmax
  sv_bot = vars.(0).map { |v| v["specific_surface_vs_nominal_outer_bottom"] }.minmax
  sv_top = vars.(0).map { |v| v["specific_surface_vs_nominal_outer_top"] }.minmax
  sub_bot = bots.map { |r| r["sub_floor_solid_fraction"] * 100 }.minmax
  sub_top = tops.map { |r| r["sub_floor_solid_fraction"] * 100 }.minmax
  sub_whole = vars.(0).map { |v| v["sub_floor_solid_fraction_whole_part"] * 100 }.minmax
  gap_axis = vars.(0).map { |v| v["worst_relative_gap_to_phase_map_outside_core"] * 100 }.max
  da_below = vars.(0).map { |v| v["anisotropy_read_below_phase_map_outside_core"] * 100 }.minmax

  anchors_seen += anchor(failures, canon, "top-outer compressed/elongated stretch",
                         /до \*\*([0-9.]+)–([0-9.]+)\*\* номіналу своєї оболонки, і видовжена до \*\*([0-9.]+)–([0-9.]+)\*\*/,
                         [ lam_min[0], lam_min[1], lam_max[0], lam_max[1] ], 2)
  anchors_seen += anchor(failures, canon, "top-outer DA and tilt",
                         /нахиленої на ([0-9]+)–([0-9]+)° від осі деталі/,
                         [ tilt[0].floor, tilt[1].ceil ], 0)
  anchors_seen += anchor(failures, canon, "top-outer DA",
                         /ступінь анізотропії \*\*([0-9.]+)–([0-9.]+)\*\*/,
                         [ da[0], da[1] ], 1)
  anchors_seen += anchor(failures, canon, "chord ratios",
                         /вздовж стиснутої осі — \*\*([0-9.]+)–([0-9.]+)\*\* номінальних, уздовж видовженої \*\*([0-9.]+)–([0-9.]+)\*\*/,
                         [ [ chord_solid[0], chord_pore[0] ].min, [ chord_solid[1], chord_pore[1] ].max,
                          chord_long[0], chord_long[1] ], 2)
  anchors_seen += anchor(failures, canon, "specific surface bottom→top",
                         /питома поверхня S_V росте з ([0-9.]+)–([0-9.]+) номіналу внизу до ([0-9.]+)–([0-9.]+) угорі/,
                         [ sv_bot[0], sv_bot[1], sv_top[0], sv_top[1] ], 2)
  anchors_seen += anchor(failures, canon, "print-floor share bottom→top",
                         /\*\*([0-9.]+)–([0-9.]+) % у нижній комірці зовнішньої оболонки проти ([0-9.]+)–([0-9.]+) % у верхній\*\*/,
                         [ sub_bot[0], sub_bot[1], sub_top[0], sub_top[1] ], 2)
  anchors_seen += anchor(failures, canon, "print-floor share, whole part",
                         /на цілу деталь — ([0-9.]+)–([0-9.]+) %/,
                         [ sub_whole[0], sub_whole[1] ], 2)
  anchors_seen += anchor(failures, canon, "one-signed gap to the phase map",
                         /на ([0-9]+)–([0-9]+) % МЕНШУ анізотропію, ніж мапа/,
                         [ da_below[0].floor, da_below[1].ceil ], 0)
  anchors_seen += anchor(failures, canon, "worst single-axis gap outside the core",
                         /розрив ≤ ([0-9.]+) % на окрему вісь/,
                         [ gap_axis.ceil(1) ], 1)

  # 🔑 The two ALTERNATIVES' figures live in the tracker's verdict leg, not in canon — the closed list is open
  #    work, and `00_06 §2` keeps open work in `00_07`. So this layer reads THAT file; the gate follows the fact
  #    to its home rather than asking canon to hold a number it must not.
  [ [ 1, "z_origin_mid", /член уполовину \(DA ([0-9.]+)–([0-9.]+), λmin ([0-9.]+)–([0-9.]+), S_V пласка ([0-9.]+)–([0-9.]+), найгірша комірка підлоги ≤ ([0-9.]+) %\)/ ],
   [ 2, "in_plane_only", /ОДНИМ осьовим періодом — DA ([0-9.]+)–([0-9.]+), λmin ([0-9.]+)–([0-9.]+), S_V пласка ([0-9.]+)–([0-9.]+), найгірша комірка підлоги ≤ ([0-9.]+) %/ ] ].each do |i, name, re|
    v = vars.(i)
    anchors_seen += anchor(failures, TRACKER_TEXT, "#{name} figures (00_07 HW.33)", re,
                           [ *v.map { |x| x["max_degree_of_anisotropy"] }.minmax,
                            *v.map { |x| x["min_stretch"] }.minmax,
                            *v.map { |x| x["specific_surface_vs_nominal_outer_top"] }.minmax,
                            v.map { |x| x["max_sub_floor_solid_fraction_by_cell"] * 100 }.max ], 2)
  end
end

# The controls, and the one that is NOT clean: `stepped`'s core shell straddles its own zone seam.
if (c = caches["anchor_zone1_graded_porosity"])
  anchors_seen += anchor(failures, canon, "period-constant control",
                         /контроль зі сталим періодом `graded_porosity` читає ([0-9.]+) при номіналах ([0-9.]+)\)/,
                         [ c[:cache]["variants"][0]["max_degree_of_anisotropy"],
                          c[:cache]["nominal_degree_of_anisotropy_by_shell"].max ], 2)
end
if (c = caches["anchor_zone1_stepped"])
  v = c[:cache]["variants"][0]
  core = v["rows"].select { |r| r["shell"].zero? }.map { |r| r["degree_of_anisotropy"] }.max
  clean = v["rows"].reject { |r| r["shell"].zero? }.map { |r| r["degree_of_anisotropy"] }.minmax
  anchors_seen += anchor(failures, canon, "stepped is not a clean control",
                         /ядрова оболонка читає ([0-9]\.[0-9]+) \(шви\), а шовно-чисті оболонки — ([0-9]\.[0-9]+)–([0-9]\.[0-9]+)/,
                         [ core, clean[0], clean[1] ], 2)
  anchors_seen += anchor(failures, canon, "stepped sub-floor share",
                         /`stepped` під тією самою підлогою втрачає ([0-9.]+) % металу/,
                         [ v["sub_floor_solid_fraction_whole_part"] * 100 ], 1)
end

# ── 3. DERIVATION — from the MANIFESTS, the figures canon computes rather than reads ─────────────
# γ at the rim corner = (L/R)·(P_core/P_rim − 1), and the in-plane term at the outer third's mean radius.
if graded.size >= 5
  gammas = graded.map do |_, h|
    cem = h[:cem]
    r = cem["outer_diameter_mm"] / 2.0
    (cem["length_mm"] / r) * ((cem["gyroid_period_mm"] / cem["gyroid_period_rim_mm"]) - 1.0)
  end
  ratios = graded.map { |_, h| h[:cem]["gyroid_period_mm"] / h[:cem]["gyroid_period_rim_mm"] }
  # ε at a radius: r·|P′|/P(r); the outer third's area-weighted mean radius is (2/3)(R³−r₀³)/(R²−r₀²) with r₀ = 2R/3.
  eps = graded.map do |_, h|
    cem = h[:cem]
    r_rim = cem["outer_diameter_mm"] / 2.0
    r0 = 2.0 * r_rim / 3.0
    r_mean = (2.0 / 3.0) * ((r_rim**3) - (r0**3)) / ((r_rim**2) - (r0**2))
    dp = (cem["gyroid_period_rim_mm"] - cem["gyroid_period_mm"]) / r_rim
    p_at = cem["gyroid_period_mm"] + (dp * r_mean)
    eps = r_mean * dp.abs / p_at
    # ⚠️ Canon states the SHORTENING of the radial step, ε/(1 + ε) — not ε itself. The two differ by three
    #    points at these gradients, and quoting ε under the words «коротший на» is the error this caught.
    (eps / (1.0 + eps)) * 100
  end
  anchors_seen += anchor(failures, canon, "γ at the rim corner",
                         /це ([0-9.]+)–([0-9.]+) у куті обода/,
                         gammas.minmax, 2)
  anchors_seen += anchor(failures, canon, "irreducible in-plane anisotropy P_core/P_rim",
                         /P_core\/P_rim = ([0-9.]+)–([0-9.]+)/,
                         ratios.minmax, 2)
  anchors_seen += anchor(failures, canon, "in-plane term ε in the outer third",
                         /на ([0-9]+)–([0-9]+) % у зовнішній третині/,
                         [ eps.min.floor, eps.max.ceil ], 0)
end

if failures.empty?
  puts "cellshape_canon_sync ✓ — 01_01 §5.5 matches tools/cad/cache/topology " \
       "(#{caches.size} cached SKUs, provenance + #{anchors_seen} range and derivation anchors). " \
       "⚠️ The instrument-floor and probe-length figures are NOT in a cache — their carriers are " \
       "CellShapeTests and the CellShape.cs header (this gate's declared ceiling)."
  exit 0
end

warn "cellshape_canon_sync ✗ — canon §5.5 has drifted from the cell-shape caches:"
failures.each { |f| warn "  · #{f}" }
warn "\nFix at the HOME (the cache is the measurement; canon quotes it): re-run `cellshape cem/<sku>.json`"
warn "for every shipped SKU if the instrument or the geometry moved, or correct the canon sentence if only"
warn "the prose drifted. ⛔ Never edit a cache by hand — `CellShapeTests` re-measures the rows canon quotes."
exit 1
