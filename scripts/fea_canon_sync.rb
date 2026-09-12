#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Voxel-FE cache ↔ canon drift guard (00_07 HW.33/HW.51). HARD gate, wired into docs.yml.
# Pure Ruby stdlib (json) — no .NET, no conda → CI-safe.
#
# 🔴 WHY IT EXISTS, and the reason is a measured one rather than a principle. The FE numbers landed in
# `01_01 §5.2` on 2026-09-12 with NO machine tie to the cache they came from. `tools/in_silico`'s cache
# has one (`test_doc_cache_sync.py`), but that guard hard-codes `tools/in_silico/cache` — one directory
# over and a different toolchain, so it cannot see this one. Within hours of the numbers landing, an
# adversarial read found two quoted figures already wrong: a spread stated as 0.3 % that the cache puts
# at 0.2 %, and a calibration stated to nine decimals that the cache does not support. Both were
# arithmetic ABOUT the cache, which is exactly the class a comparison can hold and prose cannot.
#
# WHAT IT CHECKS — FOUR layers, in increasing distance from the raw data (⚠️ this line said "three"
# for the hours between the fourth landing and this correction — a header is a claim about its own file,
# and the edit that falsifies it is one section below, where nothing looks at the header):
#   1. TRANSCRIPTION — every cell of the two canon tables against the cached rows.
#   2. DERIVATION — the figures canon computes FROM those rows (Gibson-Ashby at the measured density,
#      the two ratios to it, GPa at the reference solid modulus, the single-point readings, the spread).
#      This is the layer that catches a correct cache quoted into a wrong sentence.
#   3. PROVENANCE — that the cache still describes the run canon claims (SKU, topology, rod excluded).
#   4. THE FITTED TABLE — the measured Gibson-Ashby C/n against the per-resolution `gibson_ashby_fit.*`
#      family, which layers 1-3 do not read at all, plus that family's own provenance (specimen size).
#
# ⚠️ DECLARED CEILING, and it is wider than the usual one for a value guard:
#   • It judges NUMBERS, never the prose around them. A row can match perfectly under a sentence that
#     misdescribes what was measured — that is what killed the first version of this block (a header
#     calling both columns "frictionless" when only the axial case has platens at all).
#   • The reference solid modulus (110 GPa) is the canon Ti-6Al-4V baseline, NOT a property of the run:
#     the alloy is bake-off-gated. If canon re-bases it, this guard must be told; it cannot infer it.
#   • It does not re-run the FE. A cache that is internally consistent and physically wrong passes.
#   • Only the pine SKU is pinned, because only pine is cached. A second SKU needs a second row here.

require "json"

ROOT = File.expand_path("..", __dir__)
CANON = File.join(ROOT, "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md")
SWEEP = File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.json")
LADDER = File.join(ROOT, "tools/cad/cache/fea/size_effect_ladder.network.json")

# Canon's reference solid modulus for the GPa column (01_01 §5.2 table: Ti-6Al-4V ~110–120 GPa).
E_SOLID_GPA = 110.0

failures = []
def flag(failures, what, expected, found)
  failures << "#{what}: canon says #{found}, cache gives #{expected}"
end

sweep = JSON.parse(File.read(SWEEP))
ladder = JSON.parse(File.read(LADDER))
canon = File.read(CANON)

# ── 3. PROVENANCE ────────────────────────────────────────────────────────────────────────────────
failures << "sweep cache is not the pine SKU (#{sweep['cem']})" unless sweep["cem"] == "anchor_zone1_pine"
failures << "sweep cache is not the network branch (#{sweep['topology']})" unless sweep["topology"] == "network"
failures << "sweep cache now INCLUDES the bus rod — canon says the rod is excluded" if sweep["with_bus_rod"]
failures << "a sweep row did not converge — canon must not quote it" unless sweep["rows"].all? { |r| r["converged"] }
failures << "a ladder rung did not converge" unless ladder["rows"].all? { |r| r["converged"] }

# ── 1. TRANSCRIPTION — the sweep table ───────────────────────────────────────────────────────────
# Rows read `| період/N · X мм | axial | radial |`; anchor on the divisor, never on position.
sweep["rows"].each do |row|
  div = row["step_divisor"]
  # ⚠️ Read the CELLS, never a scan of the whole line: the label cell carries the step in mm, so a
  # naive number-scan hands you 0.333 where 0.1087 belongs — and the finest row is bolded, so the
  # anchor has to tolerate the markers. Both bit on this guard's first run.
  line = canon.lines.find { |l| l =~ /^\|[^|]*період\/#{div}\b/ }
  unless line
    failures << "canon has no sweep row for період/#{div} — the table and the cache have different shapes"
    next
  end
  cells = line.split("|").map { |c| c.strip.delete("*`") }.reject(&:empty?)
  axial, radial = cells[1].to_f, cells[2].to_f
  flag(failures, "sweep період/#{div} axial", row["axial_ratio"].round(4), axial) if (axial - row["axial_ratio"]).abs > 5e-5
  flag(failures, "sweep період/#{div} radial", row["radial_ratio"].round(4), radial) if (radial - row["radial_ratio"]).abs > 5e-5
end

# ── 1. TRANSCRIPTION — the ladder table ──────────────────────────────────────────────────────────
ladder_line = canon[/^\| `E_app\/E_solid` \|(.+)\|$/, 1]
if ladder_line.nil?
  failures << "canon has no ladder row — the size-effect table is gone or renamed"
else
  quoted = ladder_line.split("|").map(&:strip).reject(&:empty?).map(&:to_f)
  cached = ladder["rows"].map { |r| r["axial_ratio"] }
  if quoted.size != cached.size
    failures << "ladder has #{cached.size} rungs cached but #{quoted.size} quoted"
  else
    quoted.each_with_index do |q, i|
      flag(failures, "ladder rung #{ladder['rows'][i]['cells_per_side']} cell(s)", cached[i].round(4), q) if (q - cached[i]).abs > 5e-5
    end
  end
end

# ── 2. DERIVATION ────────────────────────────────────────────────────────────────────────────────
finest = sweep["rows"].min_by { |r| r["step_mm"] }
rho_part = 1.0 - finest["porosity"]
ga_part = rho_part**2

# 🔴 Every derivation anchor is COUNTED, and a miss is a failure in its own right. A check whose
# regex stops matching goes silently green — measured on this guard's own first mutation run, where a
# reworded sentence had already disarmed the porosity comparison while the run still printed ✓. So the
# question is never "did anything mismatch" but "did every check get a chance to".
anchors = 0
if (m = canon[/Порозність тут ([0-9.]+) %/, 1])
  anchors += 1
  flag(failures, "measured porosity", (finest["porosity"] * 100).round(1), m.to_f) if (m.to_f - finest["porosity"] * 100).abs > 0.05
end
# ρ and the Gibson-Ashby value live in the same table row, so one match yields both.
if (ga_row = canon.match(/при тій самій ρ = (?<rho>[0-9.]+)\*\* \| \*\*(?<ga>[0-9.]+)\*\*/))
  anchors += 1
  rho_q, ga_q = ga_row[:rho].to_f, ga_row[:ga].to_f
  flag(failures, "ρ of the part", rho_part.round(3), rho_q) if (rho_q - rho_part).abs > 5e-4
  flag(failures, "Gibson-Ashby C·ρ² at that ρ", ga_part.round(3), ga_q) if (ga_q - ga_part).abs > 5e-4
end

axial_share = finest["axial_ratio"] / ga_part
radial_share = finest["radial_ratio"] / ga_part
if (m = canon[/становить \*\*≈([0-9.]+) від Gibson-Ashby\*\*, радіальна — \*\*≈([0-9.]+)\*\*/, 0])
  anchors += 1
  a_q, r_q = m.scan(/([0-9]\.[0-9]+)/).flatten.map(&:to_f)
  flag(failures, "axial share of Gibson-Ashby", axial_share.round(2), a_q) if (a_q - axial_share).abs > 5e-3
  flag(failures, "radial share of Gibson-Ashby", radial_share.round(2), r_q) if (r_q - radial_share).abs > 5e-3
end
if (m = canon[/\*\*≈([0-9.]+) ГПа осьово\*\* і \*\*≈([0-9.]+) ГПа радіально\*\*/, 0])
  anchors += 1
  a_q, r_q = m.scan(/([0-9]+\.[0-9]+)/).flatten.map(&:to_f)
  flag(failures, "axial GPa at #{E_SOLID_GPA}", (finest['axial_ratio'] * E_SOLID_GPA).round(1), a_q) if (a_q - finest["axial_ratio"] * E_SOLID_GPA).abs > 0.06
  flag(failures, "radial GPa at #{E_SOLID_GPA}", (finest['radial_ratio'] * E_SOLID_GPA).round(1), r_q) if (r_q - finest["radial_ratio"] * E_SOLID_GPA).abs > 0.06
end

# The ladder's own coefficient — canon fits C at n = 2 and n at C = 1 on the CUBE, not the part.
top = ladder["rows"].max_by { |r| r["cells_per_side"] }
rho_cube = 1.0 - top["porosity"]
c_cube = top["axial_ratio"] / rho_cube**2
n_cube = Math.log(top["axial_ratio"]) / Math.log(rho_cube)
if (m = canon[/`C ≈ ([0-9.]+)` при `n = 2`, або `n ≈ ([0-9.]+)` при `C = 1`/, 0])
  anchors += 1
  c_q, n_q = m.scan(/([0-9]\.[0-9]+)/).flatten.map(&:to_f)
  flag(failures, "fitted C at n=2 (cube)", c_cube.round(2), c_q) if (c_q - c_cube).abs > 5e-3
  flag(failures, "fitted n at C=1 (cube)", n_cube.round(2), n_q) if (n_q - n_cube).abs > 5e-3
end

# The ladder spread — the figure that was already wrong once.
vals = ladder["rows"].map { |r| r["axial_ratio"] }
spread_pct = (vals.max - vals.min) / vals.min * 100.0
if (m = canon[/розкид ([0-9.]+) % від однієї комірки до восьми/, 1])
  anchors += 1
  ends_pct = (vals.last - vals.first).abs / vals.first * 100.0
  flag(failures, "ladder end-to-end spread", ends_pct.round(1), m.to_f) if (m.to_f - ends_pct).abs > 0.05
end
if (m = canon[/повний розкид по всіх шести рунгах ([0-9.]+) %/, 1])
  anchors += 1
  flag(failures, "ladder full spread", spread_pct.round(2), m.to_f) if (m.to_f - spread_pct).abs > 0.01
end

# ── The WITH-ROD run: a second cache file, and canon quotes it in prose rather than a table. ─────
# ⚠️ It is pinned here rather than left to prose because it is the number a reader will reach for when
# they say "the part": the rod moves the axial figure by ~9 % and the radial by nothing, so quoting the
# wrong one of the two is a silent 9 % error in exactly the direction that flatters us.
rod_path = File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.with_rod.json")
if File.exist?(rod_path)
  rod = JSON.parse(File.read(rod_path))
  failures << "with-rod cache does NOT include the rod — the file contradicts its own name" unless rod["with_bus_rod"]
  failures << "a with-rod row did not converge" unless rod["rows"].all? { |r| r["converged"] }
  rod_row = rod["rows"].min_by { |r| r["step_mm"] }
  # ⚠️ NAMED captures, not a scan: the sentence carries four numbers including the rod diameter and
  # the annulus baseline, and a positional scan hands you them in the wrong slots — it did, first run.
  if (m = canon.match(/\*\*осьова (?<a>[0-9.]+)\*\* \(проти (?<base>[0-9.]+) самої кільцевої зони, тобто монолітний Ø1\.0 додає \*\*\+(?<g>[0-9]+) %\*\*\) і \*\*радіальна (?<r>[0-9.]+)\*\*/))
    anchors += 1
    a_q, gain_q, r_q = m[:a].to_f, m[:g].to_f, m[:r].to_f
    flag(failures, "with-rod baseline (the annulus figure it is compared against)",
         finest["axial_ratio"].round(4), m[:base].to_f) if (m[:base].to_f - finest["axial_ratio"]).abs > 5e-5
    flag(failures, "with-rod axial", rod_row["axial_ratio"].round(4), a_q) if (a_q - rod_row["axial_ratio"]).abs > 5e-5
    flag(failures, "with-rod radial", rod_row["radial_ratio"].round(4), r_q) if (r_q - rod_row["radial_ratio"]).abs > 5e-5
    gain = (rod_row["axial_ratio"] / finest["axial_ratio"] - 1.0) * 100.0
    flag(failures, "rod axial gain %", gain.round, gain_q) if (gain_q - gain).abs > 0.6
  end
else
  failures << "the with-rod cache is missing — canon quotes it (`--with-rod`), so it must be committed"
end

# ── 4. THE FITTED GIBSON-ASHBY TABLE (HW.33) ─────────────────────────────────────────────────────
#
# 🔴 Added 2026-09-12, and the reason is this guard's OWN founding lesson applied one file over: the
# C/n table landed in §5.2 sourced from `gibson_ashby_fit.*.json`, which layers 1–3 do not read at all,
# so a correct cache quoted into a wrong cell would have passed green. ⚠️ The cache is PER-RESOLUTION
# by filename on purpose — a single `gibson_ashby_fit.network.json` held only the last run, so two of
# the three quoted rows had no machine tie by construction.
#
# ⛔ DECLARED CEILING: this pins the FIT, never the SWEEP ROWS it was fitted to. A cache whose eight
# (ρ, E) pairs are wrong but whose regression is arithmetically right passes here; the pairs are held
# only by the FE solver's own pins (VoxelFeaTests), not by canon.
FIT_ROWS = {
  "ґратка (куб 2 комірки)" => { glob: "tools/cad/cache/fea/gibson_ashby_fit.network.s%<n>d.json", label: "період/%<n>d", cells: 2 },
  "деталь (кільцева зона Ø11×40)" => { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d" }
}.freeze

fit_rows_seen = 0
# ⚠️ The AXIS cell is part of the KEY, not decoration: the cache carries a radial fit too (`fit_radial_*`,
# `null` until `--with-radial` is run), and the anchor's load-bearing axis is the RADIAL one — so a row
# that ever says «радіальна» must read a DIFFERENT field, and silently reading the axial one there would
# be the exact substitution this guard exists to prevent.
canon.scan(/^\| \*{0,2}([^|*]+?)\*{0,2} \| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}([^|*]+?)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|$/) do
  specimen, div, axis, c_q, n_q, r2_q = Regexp.last_match.captures
  spec = FIT_ROWS[specimen.strip]
  next failures << "fit table names an unknown specimen '#{specimen.strip}' — add it to FIT_ROWS or fix canon" if spec.nil?

  path = File.join(ROOT, format(spec[:glob], n: div.to_i))
  next failures << "fit row #{specimen.strip} #{div} quotes a cache that is not committed (#{spec[:glob] % { n: div.to_i }})" unless File.exist?(path)

  fit_rows_seen += 1
  f = JSON.parse(File.read(path))
  unless axis.strip == "осьова"
    failures << "fit row #{specimen.strip} /#{div} declares axis '#{axis.strip}' — only the AXIAL fit is "\
                "cached (`fit_radial_*` is null until `--with-radial`); this guard would silently compare "\
                "an axial number against a radial claim"
    next
  end
  c_cached = f["fit_c"] || f["fit_axial_c"]
  n_cached = f["fit_n"] || f["fit_axial_n"]
  r2_cached = f["fit_r_squared_log"] || f["fit_axial_r_squared_log"]
  failures << "fit cache #{File.basename(path)} is not the network branch (#{f['topology']})" unless f["topology"] == "network"
  failures << "fit cache #{File.basename(path)} has a non-converged row" unless f["rows"].all? { |r| r["converged"] }
  # 🔴 PROVENANCE of the fit cache, and it closes a hole the FILENAME leaves open: the lattice file is
  # named by topology and steps-per-period only, while the verb also takes `--cells` (default THREE) and
  # every committed row was measured on TWO. So a bare `fea --fit` lands exactly on a canon-pinned file
  # with a different SPECIMEN — the numbers would differ and red, but as "canon drifted", which sends the
  # reader to edit canon rather than to re-run. Naming the specimen here makes the message true.
  if spec.key?(:cells)
    failures << "fit cache #{File.basename(path)} was measured on #{f['cells_per_side']} cells a side, "\
                "not #{spec[:cells]} — a bare `fea --fit` defaults to --cells 3 and OVERWRITES this file; "\
                "re-run with the full flag set" unless f["cells_per_side"] == spec[:cells]
  end
  failures << "fit cache #{File.basename(path)} INCLUDES the bus rod — the quoted row is the lattice" if f["with_bus_rod"]
  # ⚠️ Compare at the PRECISION CANON QUOTES, not at a fixed epsilon: a fixed 5e-4 sits exactly on the
  # rounding boundary for a 3-decimal quote (1.1695 → "1.170" differs by 0.0005 in binary floating
  # point and reds a CORRECT transcription). Rounding the cache to the quoted decimals makes the
  # comparison exact and lets canon choose its own precision per row.
  # ⊕ The comparison is on STRINGS, and that is not a style choice: a float equality after rounding is
  # what `Lint/FloatComparison` warns about, and formatting both sides to the quoted precision removes
  # the question instead of suppressing it.
  at_quoted = lambda do |cached, quoted|
    [ format("%.#{quoted.include?(".") ? quoted.split(".").last.length : 0}f", cached), quoted ]
  end
  { "C" => [ c_cached, c_q ], "n" => [ n_cached, n_q ], "R²" => [ r2_cached, r2_q ] }.each do |what, (cached, quoted)|
    rendered, as_written = at_quoted.call(cached, quoted)
    flag(failures, "fit #{what} (#{specimen.strip}, /#{div})", rendered, as_written) if rendered != as_written
  end
end

EXPECTED_FIT_ROWS = 5
if fit_rows_seen < EXPECTED_FIT_ROWS
  failures << "only #{fit_rows_seen} of #{EXPECTED_FIT_ROWS} fitted-coefficient rows matched — a canon "\
              "rewording has DISARMED the C/n comparison; fix the row shape, do not lower this number"
end

EXPECTED_ANCHORS = 8
if anchors < EXPECTED_ANCHORS
  failures << "only #{anchors} of #{EXPECTED_ANCHORS} derivation anchors matched — a canon rewording has "\
              "DISARMED a comparison; find the reworded sentence, do not lower this number"
end

if failures.empty?
  puts "fea_canon_sync ✓ — 01_01 §5.2 matches tools/cad/cache/fea (transcription + #{anchors} derivation anchors + provenance)"
  exit 0
end

warn "fea_canon_sync ✗ — canon §5.2 has drifted from the FE cache:"
failures.each { |f| warn "  · #{f}" }
warn "\nFix at the HOME (the cache is the measurement; canon quotes it) — re-run `dotnet run -- fea … --sweep`"
warn "and `fea --ladder` if the geometry moved, or correct the canon sentence if only the prose drifted."
exit 1
