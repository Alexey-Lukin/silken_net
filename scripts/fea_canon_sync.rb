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
# WHAT IT CHECKS — the numbered layers below, in increasing distance from the raw data. ⛔ No count here on
# purpose: this line said "three" while four stood, then "six" while seven stood — a header is a claim about its
# own file, and the edit that falsifies it lands one section below, where nothing looks at the header. The list
# IS the roster; a new layer adds a row to it.
#   1. TRANSCRIPTION — every cell of the two canon tables against the cached rows.
#   2. DERIVATION — the figures canon computes FROM those rows (Gibson-Ashby at the measured density,
#      the two ratios to it, GPa at the reference solid modulus, the single-point readings, the spread).
#      This is the layer that catches a correct cache quoted into a wrong sentence.
#   3. PROVENANCE — that the cache still describes the run canon claims (SKU, topology, rod excluded).
#   4. THE FITTED TABLE — the measured Gibson-Ashby C/n against the per-resolution `gibson_ashby_fit.*`
#      family, which layers 1-3 do not read at all, plus that family's own provenance (specimen size).
#   5. THE FACE-OFFSET SENSITIVITY TABLE — each row against its per-row `dilation_sensitivity.*` file, and
#      the zero row against the pinned step sweep FIELD FOR FIELD, which is the identity control itself.
#   6. THE GRADED-POROSITY PAIR (§5.5) — graded part against its uniform twin at equal mass, recomputed from
#      two cache families by the same log-log interpolation canon describes.
#   7. THE CANONICAL PAIR (§5.2/§5.5) — the ratified lattice · axial · `/32` C/n wherever canon states it in prose,
#      and the two E figures canon computes with it, re-derived at the tolerance each input actually carries.
#   8. THE PERIODIC TENSOR AND FIELD (§5.2, HW.23) — the effective-tensor ladder and the field-quantile rows against
#      `periodic_homogenization.*`, that file's provenance and controls, and every sentence canon derives from it —
#      including the one that sets it beside the PART's two readings, recomputed by `105`'s own Richardson rule.
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
# The bake-off caveat is NOT repeated here — it is in this file's DECLARED CEILING block above.
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
# ERA, not the rod question it used to ask — same vocabulary as layers 4 and 5, mechanism documented at layer 4.
# The old read (`if sweep["with_bus_rod"]`) went degenerate the day the welded branch stopped emitting the key:
# nil is falsy, so it could never fire again. Absence is the live discriminator now.
failures << "sweep cache carries `with_bus_rod` — it predates the welded branch (00_07 HW.1), and the whole "\
            "step sweep canon quotes must be the body canon describes" if sweep.key?("with_bus_rod")
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

# ── 1. TRANSCRIPTION — the POROSITY column of the sweep, which lives in PROSE, not in the table ───
# 🔴 Added 2026-09-18 because it was caught by hand, not by this guard. §5.2 clears a named suspicion —
# "is the extrapolation poisoned by voxel-dependent porosity (HW.49)?" — by quoting the porosity of all
# four sweep rows; the table above carries only axial and radial, so those four numbers had no machine
# tie at all. The welded branch (00_07 HW.1) moved every one of them, and the sentence went on standing
# over a retired specimen while layers 1–5 stayed green. ⛔ DECLARED CEILING: it pins the four numbers
# and the ORDER the sentence itself names, never the verdict drawn from them — that a 0.15 pp band is
# small enough to clear the suspicion is a judgement, and judgements do not go in guards.
if (m = canon.match(/\*\*([0-9.]+(?: · [0-9.]+)+) %\*\* на `(період\/[^`]+)`/))
  anchors_porosity = m[1].split(" · ")
  divisors = m[2].scan(/\d+/).map(&:to_i)
  if anchors_porosity.size != divisors.size
    failures << "the sweep-porosity sentence quotes #{anchors_porosity.size} values for #{divisors.size} divisors"
  elsif divisors.size != sweep["rows"].size
    failures << "the sweep-porosity sentence names #{divisors.size} divisors but the cache carries "\
                "#{sweep['rows'].size} rows — a row was added or dropped and the sentence did not follow"
  else
    divisors.each_with_index do |div, i|
      row = sweep["rows"].find { |r| r["step_divisor"] == div }
      next failures << "the sweep-porosity sentence names період/#{div}, which the cache does not carry" if row.nil?

      rendered = format("%.2f", row["porosity"] * 100.0)
      flag(failures, "sweep porosity період/#{div}", rendered, anchors_porosity[i]) if rendered != anchors_porosity[i]
    end
  end
else
  failures << "the sweep-porosity sentence is gone or reworded — §5.2 clears the HW.49 suspicion with those "\
              "four numbers, and without them the clearance is prose over nothing; fix the sentence shape"
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

# The Richardson row of the sweep table and the one sentence that derives from it — UNPINNED until 2026-10-21, and
# stale from the welded re-measurement of 2026-09-18 until then: the row still carried the printed-core era's band, so
# a correct cache stood under a wrong extrapolation for a month with every layer green.
pair = sweep["rows"].sort_by { |r| r["step_mm"] }.first(2)
richardson = ->(key, order) { pair[0][key] + ((pair[0][key] - pair[1][key]) / (((pair[1]["step_mm"] / pair[0]["step_mm"])**order) - 1.0)) }
if (m = canon.match(/\| екстраполяція Річардсона \(1-й ⊥ 2-й порядок\) \| ([0-9.]+)–([0-9.]+) \| ([0-9.]+)–([0-9.]+) \|/))
  anchors += 1
  want = [ richardson.call("axial_ratio", 1), richardson.call("axial_ratio", 2), richardson.call("radial_ratio", 1), richardson.call("radial_ratio", 2) ]
  m.captures.zip(want).each { |q, v| flag(failures, "Richardson row of the sweep table", format("%.3f", v), q) if format("%.3f", v) != q }
end
if (m = canon.match(/екстраполяція Річардсона опускає радіальну на ≈ (\d+)–(\d+) %/))
  anchors += 1
  drops = [ 2, 1 ].map { |o| (1 - (richardson.call("radial_ratio", o) / pair[0]["radial_ratio"])) * 100 }
  m.captures.zip(drops).each { |q, v| flag(failures, "Richardson radial drop", format("%.0f", v), q) if format("%.0f", v) != q }
end

# ── The WITH-ROD run: the RECORD of a branch that no longer exists. ──────────────────────────────
# ⚠️ Pinned rather than left to prose because it is the number a reader reaches for when they say "the
# part": the printed rod moved the axial figure by ~9 % and the radial by nothing.
# 🔴 Since 2026-09-18 BOTH sides of that comparison are FROZEN EVIDENCE, not live measurements: the
# welded branch removed the printed core from the anode and `fea --with-rod` with it (00_07 HW.1), so
# neither the with-rod row nor the annulus baseline it is quoted against can be re-measured by any verb
# in this tree. The baseline therefore reads from the FROZEN pre-A sweep, never from the live one — a
# comparison against today's sweep would be two different specimens wearing one sentence.
rod_path = File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.with_rod.json")
frozen_path = File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.printed_core_branch.json")
frozen = File.exist?(frozen_path) ? JSON.parse(File.read(frozen_path)) : nil
failures << "the frozen printed-core sweep is missing — canon quotes its baseline, so it must be committed" if frozen.nil?
frozen_finest = frozen && frozen["rows"].min_by { |r| r["step_mm"] }
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
    flag(failures, "with-rod baseline (the FROZEN pre-A annulus it is compared against)",
         frozen_finest["axial_ratio"].round(4), m[:base].to_f) if frozen_finest && (m[:base].to_f - frozen_finest["axial_ratio"]).abs > 5e-5
    flag(failures, "with-rod axial", rod_row["axial_ratio"].round(4), a_q) if (a_q - rod_row["axial_ratio"]).abs > 5e-5
    flag(failures, "with-rod radial", rod_row["radial_ratio"].round(4), r_q) if (r_q - rod_row["radial_ratio"]).abs > 5e-5
    gain = frozen_finest ? ((rod_row["axial_ratio"] / frozen_finest["axial_ratio"] - 1.0) * 100.0) : gain_q
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
  # ⚠️ BOTH spellings are known on purpose, and the pair is what makes the era tie below readable. If only the
  # marked one were listed, dropping the caveat would red as "unknown specimen — add it to FIT_ROWS", which is
  # the one instruction that must NOT be followed: it invites re-adding the row with no era tie at all. Listing
  # both lets the CACHE decide which spelling is true and lets the message say so.
  # The welded branch (00_07 HW.1) prints the anode WITHOUT a core, so the re-measured specimen is not an annulus
  # at all — it carries its own name, and the name is what separates the two eras in the table.
  "деталь (ґратка до осі Ø11×40)" =>
    { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d" },
  "деталь (кільцева зона Ø11×40, знесена гілка)" =>
    { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d", retired: true },
  # ⛔ The annulus WITHOUT the caveat names a specimen no verb produces — listed only so that dropping the caveat
  # reds with the right instruction (rename to the lattice-to-the-axis specimen) instead of «add it to FIT_ROWS».
  "деталь (кільцева зона Ø11×40)" =>
    { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d",
      renamed_to: "деталь (ґратка до осі Ø11×40)" }
}.freeze

fit_rows_seen = 0
# ⚠️ The AXIS cell is part of the KEY, not decoration: the part cache carries a radial fit too (`fit_radial_*`),
# the anchor's load-bearing axis is the RADIAL one, and the two axes disagree about WHICH member of the formula
# is off (01_01 §5.2) — so a «радіальна» row reads the radial fields and nothing else, and silently reading the
# axial one there would be the exact substitution this guard exists to prevent.
canon.scan(/^\| \*{0,2}([^|*]+?)\*{0,2} \| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}([^|*]+?)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|$/) do
  specimen, div, axis, c_q, n_q, r2_q = Regexp.last_match.captures
  spec = FIT_ROWS[specimen.strip]
  next failures << "fit table names an unknown specimen '#{specimen.strip}' — add it to FIT_ROWS or fix canon" if spec.nil?
  if spec[:renamed_to]
    next failures << "fit row '#{specimen.strip}' /#{div} names the retired annulus as if it were current — a row "\
                     "re-measured on the welded body is '#{spec[:renamed_to]}'; a row still on the old cache keeps «знесена гілка»"
  end

  path = File.join(ROOT, format(spec[:glob], n: div.to_i))
  next failures << "fit row #{specimen.strip} #{div} quotes a cache that is not committed (#{spec[:glob] % { n: div.to_i }})" unless File.exist?(path)

  fit_rows_seen += 1
  f = JSON.parse(File.read(path))
  case axis.strip
  when "осьова"
    c_cached = f["fit_c"] || f["fit_axial_c"]
    n_cached = f["fit_n"] || f["fit_axial_n"]
    r2_cached = f["fit_r_squared_log"] || f["fit_axial_r_squared_log"]
  when "радіальна"
    # A radial claim against a cube cache (no radial fields at all) or against a part cache whose radial fit
    # is null — run without `--with-radial`, or refused on a step that does not divide the diameter — reds by
    # name here, instead of falling through to the axial fields.
    c_cached, n_cached, r2_cached = f.values_at("fit_radial_c", "fit_radial_n", "fit_radial_r_squared_log")
    if [ c_cached, n_cached, r2_cached ].any?(&:nil?)
      failures << "fit row #{specimen.strip} /#{div} declares axis 'радіальна' but #{File.basename(path)} carries no "\
                  "radial fit — re-run with --with-radial on a divisor that divides the diameter"
      next
    end
  else
    failures << "fit row #{specimen.strip} /#{div} declares axis '#{axis.strip}' — this guard knows «осьова» and «радіальна» only"
    next
  end
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
  # 🔴 THE ERA TIE, and it is TWO-WAY because the failure is symmetrical and both halves are silent
  # (2026-09-18). The welded branch (00_07 HW.1) took the printed core out of the anode, so the part these
  # fits were measured on — an annulus from the printed Ø1.0 rod surface to Ø11 — cannot be produced by any verb in this tree
  # any more. `with_bus_rod` survives here NOT as the rod question it was born asking (no fit was ever run
  # with the rod, so that read was dead the day it was written) but as the retired branch's own fingerprint:
  # a post-A run does not emit the key at all.
  #   · cache carries it, row does not say «знесена гілка» → canon quotes a retired specimen as current;
  #   · cache has dropped it, row still says it → the re-run landed and the caveat outlived it, so canon now
  #     under-claims its own fresh numbers. That second half is the one prose never catches, because nobody
  #     re-reads a caveat looking for a reason to delete it.
  measured_pre_a = f.key?("with_bus_rod")
  if spec[:retired] && !measured_pre_a
    failures << "fit row #{specimen.strip} /#{div}: #{File.basename(path)} no longer carries the retired branch's "\
                "`with_bus_rod` fingerprint — it was re-measured on the welded body, so the row is the lattice-to-the-axis "\
                "specimen: rename the cell to «деталь (ґратка до осі Ø11×40)» instead of leaving canon under-claiming a fresh number"
  elsif !spec[:retired] && measured_pre_a
    failures << "fit row #{specimen.strip} /#{div}: #{File.basename(path)} still carries `with_bus_rod`, i.e. it was "\
                "measured BEFORE the welded branch (00_07 HW.1) — the row must say «знесена гілка» or be re-run"
  end
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

EXPECTED_FIT_ROWS = 8
if fit_rows_seen < EXPECTED_FIT_ROWS
  failures << "only #{fit_rows_seen} of #{EXPECTED_FIT_ROWS} fitted-coefficient rows matched — a canon "\
              "rewording has DISARMED the C/n comparison; fix the row shape, do not lower this number"
end

# ── 5. THE FACE-OFFSET SENSITIVITY TABLE (HW.51) ─────────────────────────────────────────────────────
#
# 🔴 Added 2026-09-14 with `fea --dilate`, for the same reason layer 4 exists: the rows live in a file family
# (`dilation_sensitivity.*`, one file per row) that layers 1-4 never open. Three things are held, and the third is the
# one prose cannot hold at all:
#   (a) TRANSCRIPTION — porosity, axial and radial of every quoted row, at the precision canon quotes;
#   (b) PROVENANCE — the file's own element, offset and step agree with its name and its row; it is clipped to the part
#       body, rod-free, network, converged (the SOLVER's flag, NOT step convergence — see the ceiling below) — and it
#       calls itself a SENSITIVITY, never the printed body;
#   (c) THE IDENTITY CONTROL — the zero-offset row equals the pinned step sweep's row of the same divisor EXACTLY, field
#       for field. That equality is the whole ground for reading every other row as "the intent plus an offset", so a
#       drift there is not a stale digit — it means the wrapper, the sampler or the solver moved under the curve.
# ⛔ DECLARED CEILING: it pins the curve canon quotes, never its step convergence (the curve is measured at one step) and
#    never the geometry of the dilation — identity, clip, frame, monotonicity and the discretisation shortfall are
#    VoxelFeaTests' pins, which this guard cannot see.
DILATION_DIR = File.join(ROOT, "tools/cad/cache/fea")
dilation_rows_seen = 0
canon.scan(/^\| \*{0,2}(нуль крізь обгортку|downskin|iso)\*{0,2} \| \*{0,2}([0-9.]+) мм\*{0,2} \| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}([0-9.]+) %\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|$/) do
  element, offset_q, div, porosity_q, axial_q, radial_q = Regexp.last_match.captures
  microns = (offset_q.to_f * 1000).round
  zero = element == "нуль крізь обгортку"
  next failures << "sensitivity row '#{element} · #{offset_q} мм' pairs an element with the wrong offset" if zero != microns.zero?

  name = "dilation_sensitivity.anchor_zone1_pine.#{zero ? '' : "#{element}."}f#{microns}um.d#{div}.json"
  path = File.join(DILATION_DIR, name)
  next failures << "sensitivity row '#{element} · #{offset_q} мм · період/#{div}' quotes #{name}, which is not committed" unless File.exist?(path)

  dilation_rows_seen += 1
  f = JSON.parse(File.read(path))
  what = "sensitivity #{element} #{offset_q} мм /#{div}"
  failures << "#{what}: the file is not the pine network part" unless f["cem"] == "anchor_zone1_pine" && f["topology"] == "network"
  # The ERA half of the provenance, in the same vocabulary layer 4 uses — read the comment there for the mechanism.
  # This family is the MIRROR case: every row was re-measured on the welded body 2026-09-18, so the absence of
  # `with_bus_rod` is what makes it current. ⚠️ The check used to read `== false`, which was the RIGHT question while
  # both branches could be built and became unsatisfiable the moment one could not — a guard whose subject stopped
  # existing does not go quiet, it goes red on correct files and sends the reader to re-run a measurement that is
  # already fresh. Asserting ABSENCE keeps the same discrimination pointed at the case that can still happen: a
  # pre-A row quoted into this table.
  failures << "#{what}: the file carries `with_bus_rod`, i.e. it predates the welded branch (00_07 HW.1) — "\
              "the sensitivity curve must be measured on the body canon describes" if f.key?("with_bus_rod")
  failures << "#{what}: the file names element #{f['dilation_element'].inspect}" unless f["dilation_element"] == (zero ? nil : element)
  failures << "#{what}: the file carries offset #{f['face_offset_mm']} mm and step /#{f['step_divisor']}" unless (f["face_offset_mm"] * 1000).round == microns && f["step_divisor"] == div.to_i
  failures << "#{what}: the dilation was not clipped to the part body" unless f["clipped_to_part_body"] == true
  failures << "#{what}: a row that did not converge is quoted" unless f["converged"]
  failures << "#{what}: the file does not call itself a SENSITIVITY of the intent — a dilated row must never read as the printed body" unless f["_note"].to_s.include?("SENSITIVITY") && f["_note"].to_s.include?("NOT the printed body")

  { "porosity" => [ f["porosity"] * 100.0, porosity_q ], "axial" => [ f["axial_ratio"], axial_q ], "radial" => [ f["radial_ratio"], radial_q ] }.each do |cell, (cached, quoted)|
    rendered = format("%.#{quoted.include?('.') ? quoted.split('.').last.length : 0}f", cached)
    flag(failures, "#{what} #{cell}", rendered, quoted) if rendered != quoted
  end

  pinned = sweep["rows"].find { |r| r["step_divisor"] == div.to_i }
  next failures << "#{what}: період/#{div} is a step the pinned sweep does not carry — the row has no intent to be read against" if pinned.nil?

  # A dilation only adds metal, and in linear elasticity under prescribed displacements added metal cannot lower either
  # stiffness — so a row that is not denser AND stiffer than the intent of its own step indicts the instrument. It also
  # carries canon's sentence that print excess only ever widens the gap to the wood (§5.1).
  unless zero || (f["porosity"] < pinned["porosity"] && f["axial_ratio"] > pinned["axial_ratio"] && f["radial_ratio"] > pinned["radial_ratio"])
    failures << "#{what}: the row is not denser and stiffer than the intent at період/#{div} — a dilation cannot soften the part"
  end
  next unless zero

  %w[elements dofs porosity axial_ratio radial_ratio discarded_island_fraction axial_iterations radial_iterations].each do |key|
    next if f[key] == pinned[key]

    failures << "IDENTITY CONTROL broken: the zero row's #{key} is #{f[key].inspect} through the wrapper and #{pinned[key].inspect} "\
                "in the pinned sweep at /#{div} — the wrapper, the sampler or the solver moved under the whole curve"
  end
end

EXPECTED_DILATION_ROWS = 9
if dilation_rows_seen < EXPECTED_DILATION_ROWS
  failures << "only #{dilation_rows_seen} of #{EXPECTED_DILATION_ROWS} face-offset sensitivity rows matched — a canon "\
              "rewording has DISARMED the comparison; fix the row shape, do not lower this number"
end

# The two sentences canon DERIVES from that table — both are statements about which cells cross a line, so a
# re-measurement that moves a cell across it must red here rather than leave the prose standing over new numbers.
dilation_file = lambda do |element, microns, div|
  path = File.join(DILATION_DIR, "dilation_sensitivity.anchor_zone1_pine.#{element ? "#{element}." : ''}f#{microns}um.d#{div}.json")
  File.exist?(path) ? JSON.parse(File.read(path)) : nil
end
dilation_anchors = 0

# (i) the factory acceptance band 60–70 % (01_02 §1.2): only the first downskin row stays inside it, iso leaves it at once.
if canon.include?("тримає лише **downskin 0.10 мм**, а iso виходить за неї вже на **0.05 мм**")
  dilation_anchors += 1
  band = { "the zero row" => [ nil, 0 ], "downskin 0.10" => [ "downskin", 100 ], "downskin 0.25" => [ "downskin", 250 ], "iso 0.05" => [ "iso", 50 ] }
  inside = band.transform_values { |(element, microns)| (f = dilation_file.call(element, microns, 12)) && f["porosity"].between?(0.60, 0.70) }
  expected = { "the zero row" => true, "downskin 0.10" => true, "downskin 0.25" => false, "iso 0.05" => false }
  expected.each do |row, want|
    next if inside[row] == want

    failures << "factory-band sentence: canon says #{row} at період/12 is #{want ? 'inside' : 'outside'} 60–70 %, the cache says otherwise"
  end
end

# (ii) the equal-density pair: at nearly the same porosity the iso row is stiffer AXIALLY and softer RADIALLY than the
# downskin row, at both steps quoted. The percentages are relative to the downskin row of the same step.
canon.scan(/на \*\*період\/(\d+)\*\* iso 0\.05 мм жорсткіший осьово на \*\*\+([0-9.]+) %\*\* і мʼякший радіально на \*\*−([0-9.]+) %\*\*/) do
  div, axial_q, radial_q = Regexp.last_match.captures
  downskin, iso = dilation_file.call("downskin", 250, div), dilation_file.call("iso", 50, div)
  next failures << "equal-density pair at період/#{div}: a row is not committed" if downskin.nil? || iso.nil?

  dilation_anchors += 1
  { "axial gain" => [ (iso["axial_ratio"] / downskin["axial_ratio"] - 1.0) * 100.0, axial_q ],
    "radial loss" => [ (1.0 - iso["radial_ratio"] / downskin["radial_ratio"]) * 100.0, radial_q ] }.each do |what, (cached, quoted)|
    rendered = format("%.#{quoted.include?('.') ? quoted.split('.').last.length : 0}f", cached)
    flag(failures, "equal-density pair /#{div} #{what} %", rendered, quoted) if rendered != quoted
  end
end

EXPECTED_DILATION_ANCHORS = 3
if dilation_anchors < EXPECTED_DILATION_ANCHORS
  failures << "only #{dilation_anchors} of #{EXPECTED_DILATION_ANCHORS} sensitivity derivation anchors matched — a canon "\
              "rewording has DISARMED a comparison; find the reworded sentence, do not lower this number"
end

EXPECTED_ANCHORS = 10
if anchors < EXPECTED_ANCHORS
  failures << "only #{anchors} of #{EXPECTED_ANCHORS} derivation anchors matched — a canon rewording has "\
              "DISARMED a comparison; find the reworded sentence, do not lower this number"
end

# ── 6. THE GRADED-POROSITY PAIR AT EQUAL MASS (01_01 §5.5, HW.33) ────────────────────────────────────
#
# 🔴 Added 2026-09-18, because these numbers had no machine tie at all and went stale in the one way prose cannot
# notice: they lived in a CLOSED tracker leg, the welded branch re-measured the caches they cite, and the leg went on
# quoting the annulus. The pair is a DERIVATION over two cache families — the graded part itself (`anchor_zone1_
# graded_porosity.h<µm>um.json`) against its uniform twin, log-log interpolated to the part's own relative density
# between the bracket walls −0.20/−0.10 of `gibson_ashby_fit.anchor_zone1_graded_porosity.h<µm>um.json` — so a
# re-run that moves either family must red here instead of leaving §5.5 standing over new numbers.
# ⛔ DECLARED CEILING: it pins the four percentages and the two porosities the sentence quotes, at the precision it
# quotes them; the reading drawn from them (mechanics does not decide the fork) is a judgement and stays prose.
graded_pair = lambda do |tag|
  part_path = File.join(DILATION_DIR, "anchor_zone1_graded_porosity.#{tag}.json")
  fit_path = File.join(DILATION_DIR, "gibson_ashby_fit.anchor_zone1_graded_porosity.#{tag}.json")
  next nil unless File.exist?(part_path) && File.exist?(fit_path)

  part = JSON.parse(File.read(part_path))["rows"].first
  rows = JSON.parse(File.read(fit_path))["rows"]
  lo = rows.find { |r| (r["wall_param"] + 0.2).abs < 1e-6 }
  hi = rows.find { |r| (r["wall_param"] + 0.1).abs < 1e-6 }
  next nil if lo.nil? || hi.nil?

  rho = 1.0 - part["porosity"]
  interp = lambda do |axis|
    x0, x1 = Math.log(lo["relative_density"]), Math.log(hi["relative_density"])
    y0, y1 = Math.log(lo["#{axis}_ratio"]), Math.log(hi["#{axis}_ratio"])
    Math.exp(y0 + ((y1 - y0) * (Math.log(rho) - x0) / (x1 - x0)))
  end
  { porosity: part["porosity"] * 100.0,
    axial: ((part["axial_ratio"] / interp.call("axial")) - 1.0) * 100.0,
    radial: ((part["radial_ratio"] / interp.call("radial")) - 1.0) * 100.0 }
end
signed = ->(s) { s.tr("−", "-").delete("+").to_f }
if (m = canon.match(/осьово \*\*([+−][0-9.]+) %\*\* · \*\*([+−][0-9.]+) %\*\* на кроках 0\.22 · 0\.183 мм.*?радіально \*\*([+−][0-9.]+) %\*\* · \*\*([+−][0-9.]+) %\*\*.*?пористості градієнтної деталі ([0-9.]+) · ([0-9.]+) %/m))
  ax220, ax183, rad220, rad183, por220, por183 = m.captures
  quoted = { "h220um" => [ ax220, rad220, por220 ], "h183um" => [ ax183, rad183, por183 ] }
  quoted.each do |tag, (ax_q, rad_q, por_q)|
    got = graded_pair.call(tag)
    next failures << "graded pair #{tag}: the part or its bracket fit is not committed (or lacks the −0.20/−0.10 walls)" if got.nil?

    { "axial %" => [ got[:axial], ax_q ], "radial %" => [ got[:radial], rad_q ], "porosity %" => [ got[:porosity], por_q ] }.each do |what, (cached, q)|
      digits = q.include?(".") ? q.split(".").last.length : 0
      next if (cached.round(digits) - signed.call(q)).abs < 1e-9

      flag(failures, "graded pair #{tag} #{what}", format("%+.#{digits}f", cached), q)
    end
  end
else
  failures << "the graded-pair sentence of §5.5 is gone or reworded — its four percentages and two porosities have no "\
              "other tie to the caches; fix the sentence shape, do not drop this check"
end

# ── 7. THE CANONICAL PAIR AND ITS TWO DERIVED FIGURES (01_01 §5.2 / §5.5, HW.33) ─────────────────────────
#
# ⚖️ Ratified 2026-09-18: the formula pair canon may compute with is the LATTICE cube, AXIAL, at `/32`. Canon quotes
# two numbers computed with it — the network flip of §5.2 and the 80 % example of §5.5 — that no layer derived, so
# a re-run of the cube or a reworded sentence left them standing silently. Re-derived here from
# `gibson_ashby_fit.network.s32.json` and the porosity each sentence itself quotes, at E_SOLID_GPA.
# ⊕ And the PAIR ITSELF where canon states it in prose — the ratified declaration and the §5.5 example both quote
# `C`/`n`, and until 2026-09-18 the example's two numbers were MATCHED by `[0-9.]+` and never compared, so a re-run
# of the cube could have moved the pair under a sentence that still printed the old one. (The fitted TABLE row of
# the same pair is layer 4's.) Compared at the precision canon quotes, like layer 4.
# ⛔ DECLARED CEILING on the E tolerance, and it is per SENTENCE, because the two porosities are different kinds of
# input: the 50.2 % of the flip is a ROUNDED MEASUREMENT (the run left no cache), so its rounding propagates —
# |dE/dρ|·½·10^-d(P) + ½·10^-d(E); the 80 % of «напр. 80%» is an EXACT example input, so only E's own rounding applies.
# (Propagating an example's «rounding» used to widen that tolerance to ±0.214 GPa — 2.8, 3.0 and 3.1 all passed for 2.9.)
pair_derivations = 0
pair_quotes = 0
pair_path = File.join(DILATION_DIR, "gibson_ashby_fit.network.s32.json")
if File.exist?(pair_path)
  pair = JSON.parse(File.read(pair_path))
  c_pair, n_pair = pair["fit_c"], pair["fit_n"]
  decimals = ->(s) { s.include?(".") ? s.split(".").last.length : 0 }
  at_quoted = ->(cached, quoted) { format("%.#{decimals.call(quoted)}f", cached) }
  compare_pair = lambda do |what, c_q, n_q|
    pair_quotes += 1
    { "C" => [ c_pair, c_q ], "n" => [ n_pair, n_q ] }.each do |sym, (cached, quoted)|
      rendered = at_quoted.call(cached, quoted)
      flag(failures, "canonical pair #{sym} in #{what}", rendered, quoted) if rendered != quoted
    end
  end

  if (m = canon.match(/Канонна пара — ґратка · осьова · `\/32`: `C` ([0-9.]+) · `n` ([0-9.]+)/))
    compare_pair.call("the ratified declaration", *m.captures)
  else
    failures << "canonical pair: the ratified declaration («Канонна пара — ґратка · осьова · `/32`: `C` … · `n` …») is "\
                "gone or reworded — it states the pair, fix its shape, do not drop this check"
  end

  [
    [ "§5.2 network flip", :measured,
      /network виходить на ([0-9.]+) % пористості.*?при канонній парі §5\.2 \(ґратка · осьова · `\/32` — ґраткова оцінка\) та сама густина дає ([0-9.]+)\)/m ],
    [ "§5.5 80 % example", :exact,
      /напр\. ([0-9.]+)% → `C·ρ²` дає E ≈ [0-9.]+ ГПа, а при канонній парі `C` = ([0-9.]+) \/ `n` = ([0-9.]+) \(ґратка · осьова · `\/32` — ґраткова оцінка\) — ≈([0-9.]+)\)/ ]
  ].each do |what, porosity_kind, rx|
    m = canon.match(rx)
    next failures << "canonical pair: the #{what} sentence is gone or reworded — fix its shape, do not drop this check" if m.nil?

    por_q, *pair_q, e_q = m.captures
    compare_pair.call("the #{what} sentence", *pair_q) unless pair_q.empty?
    rho = 1.0 - (por_q.to_f / 100.0)
    e = c_pair * E_SOLID_GPA * (rho**n_pair)
    por_term = porosity_kind == :measured ? (n_pair * e / rho) * 0.5 * (10.0**-(decimals.call(por_q) + 2)) : 0.0
    tol = por_term + (0.5 * (10.0**-decimals.call(e_q)))
    pair_derivations += 1
    flag(failures, "canonical-pair #{what} GPa (±#{tol.round(3)})", e.round(3), e_q) if (e - e_q.to_f).abs > tol
  end
else
  failures << "canonical pair: #{pair_path} is not committed — the ratified pair has no cache to derive from"
end

# ── 8. THE PERIODIC TENSOR AND FIELD (01_01 §5.2, HW.23) ─────────────────────────────────────────────────
#
# 🔴 Added 2026-10-21 with `fea --periodic`, for the reason layers 4 and 5 exist: the numbers live in a file family
# (`periodic_homogenization.*`) no other layer opens. Held: (a) TRANSCRIPTION of both tables — the tensor ladder and the
# field quantiles at the finest rung; (b) PROVENANCE — the file calls itself periodic and a MATERIAL, is network at level
# 0.10 on one cell, at the cube ladder's period and the sweep's ν, every rung converged, and its controls sit inside the
# solver's precision; (c) DERIVATION — every number canon computes FROM the file, and the comparison with the part's two
# readings on every density-matched PAIR of basis (first- and second-order Richardson) and rung (the ladder's rungs whose
# porosity matches the part's), the part's readings built as `106` builds them (radial → C11 + C12 by the plane-strain
# normaliser, axial → E[100]).
# 🔴 Why pairs: the first version compared ONE basis against ONE rung and read a 0.4 % agreement of the deviatoric term
# off it; round 2 showed it was +3.5 % on second order, round 3 that it is −1.7 % against /24 — the ladder's own scatter
# is wider than the difference. So a difference is claimed only where it keeps ONE sign on every pair, and where it does
# not, the sentence that says «not established» is held to the sign change. «Equal step» is no basis: the raw /16 part
# row is not converged and the phase-locked cube is at another density there.
# ⚠️ Hill–Mandel here is an IDENTITY of the formulation (it holds at any CG iterate from a zero start): its check catches
# only a stress readout inconsistent with the energy (another B, another point, another sign), never a wrong solution.
# ⛔ DECLARED CEILING: it pins the numbers and the sentences built on them, never the instrument (VoxelFeaTests holds the
# closed forms) nor which of the two bodies a consumer should read — that reading is not a number.
PERIODIC = File.join(ROOT, "tools/cad/cache/fea/periodic_homogenization.network.w100.c1.json")
CACHE_105 = File.join(ROOT, "tools/in_silico/cache/mechanical/printed_part_sway_stress.json")
periodic_rows_seen = 0
periodic_anchors = 0
if File.exist?(PERIODIC)
  per = JSON.parse(File.read(PERIODIC))
  failures << "periodic cache does not call itself periodic" unless per["boundary_condition"] == "periodic"
  failures << "periodic cache is not the network branch at level 0.10 on one cell" unless per["topology"] == "network" &&
                                                                                        (per["wall_param"] - 0.10).abs < 1e-6 &&
                                                                                        per["cells_per_side"] == 1
  failures << "periodic cache's note does not call it a MATERIAL property" unless per["_note"].to_s.include?("MATERIAL")
  failures << "periodic solid calibration is #{per['solid_calibration_max_abs_error']}, not round-off" unless per["solid_calibration_max_abs_error"] < 1e-10
  # «на тому самому кроці» (against the cube ladder) and «рівний крок» (against the part) are claims about the PERIOD and
  # the STEP, and «драбини куба» one about the same LATTICE — its topology and wall level.
  failures << "periodic cache is at period #{per['period_mm']} mm, the cube ladder at #{ladder['period_mm']} mm — canon compares them at one step" unless (per["period_mm"] - ladder["period_mm"]).abs < 1e-9
  failures << "canon sets the periodic /16 cell against the cube ladder «на тому самому кроці»; the ladder is at /#{ladder['steps_per_period']}" unless ladder["steps_per_period"] == 16
  failures << "the cube ladder is #{ladder['topology']} at level #{ladder['wall_param']}, the periodic cell #{per['topology']} at #{per['wall_param']} — not one lattice" unless ladder["topology"] == per["topology"] && (ladder["wall_param"] - per["wall_param"]).abs < 1e-9
  failures << "periodic cache's ν #{per['poisson_ratio']} is not the sweep's #{sweep['poisson_ratio']}" unless (per["poisson_ratio"] - sweep["poisson_ratio"]).abs < 1e-12
  per["rows"].each do |r|
    tag = "periodic /#{r['steps_per_period']}"
    failures << "#{tag}: a rung did not converge — canon must not quote it" unless r["converged"]
    failures << "#{tag}: the stress readout is inconsistent with the energy (Hill–Mandel #{r['hill_mandel_worst']})" unless r["hill_mandel_worst"] < 1e-8
    failures << "#{tag}: reciprocity #{r['reciprocity_worst']}" unless r["reciprocity_worst"] < 1e-7
    failures << "#{tag}: a cubic family spreads by #{r['cubic_equivalent_spread']}" unless r["cubic_equivalent_spread"] < 1e-6
    r["fields"].each do |f|
      failures << "#{tag} θ #{f['theta_deg']}: field energy identity #{f['energy_identity_residual']}" unless f["energy_identity_residual"] < 1e-7
    end
  end
  rung = ->(steps) { per["rows"].find { |r| r["steps_per_period"] == steps } }
  render = ->(value, quoted) { format("%#{quoted.start_with?('+') ? '+' : ''}.#{quoted.include?('.') ? quoted.split('.').last.length : 0}f", value).sub(/\A-/, "−") }

  # (a) the tensor ladder — anchored on the 9-cell shape; no other §5.2 table has it.
  canon.scan(/^\| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}([0-9.]+) %\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|$/) do
    steps, *quoted = Regexp.last_match.captures
    r = rung.call(steps.to_i)
    next failures << "periodic table row період/#{steps} has no rung in the cache" if r.nil?

    periodic_rows_seen += 1
    cached = [ r["porosity"] * 100.0, r["C11"], r["C12"], r["C44"], r["nu_star"], r["zener"], r["E100"], r["E110"] ]
    %w[porosity C11 C12 C44 ν* A E100 E110].zip(cached, quoted).each do |cell, value, q|
      flag(failures, "periodic /#{steps} #{cell}", render.call(value, q), q) if render.call(value, q) != q
    end
  end
  EXPECTED_PERIODIC_ROWS = per["rows"].size
  if periodic_rows_seen < EXPECTED_PERIODIC_ROWS
    failures << "only #{periodic_rows_seen} of #{EXPECTED_PERIODIC_ROWS} periodic-tensor rows matched — a canon rewording has "\
                "DISARMED the comparison; fix the row shape, do not lower this number"
  end

  # (a) the field quantiles at the finest rung.
  finest = per["rows"].max_by { |r| r["steps_per_period"] }
  field_rows_seen = 0
  canon.scan(/^\| θ = ([0-9.]+)° \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \|$/) do
    theta, *quoted = Regexp.last_match.captures
    f = finest["fields"].find { |x| (x["theta_deg"] - theta.to_f).abs < 1e-9 }
    next failures << "periodic field row θ = #{theta}° has no field in the finest rung" if f.nil?

    field_rows_seen += 1
    q = f["principal_over_sigma_w"]
    cached = [ f["modulus_ratio"], q["p50"], q["p90"], q["p99"], q["p99.9"], q["max"] ]
    %w[E p50 p90 p99 p99.9 max].zip(cached, quoted).each do |cell, value, qq|
      flag(failures, "periodic field θ #{theta}° #{cell}", render.call(value, qq), qq) if render.call(value, qq) != qq
    end
  end
  if field_rows_seen < finest["fields"].size
    failures << "only #{field_rows_seen} of #{finest['fields'].size} periodic field rows matched — fix the row shape"
  end

  # (c) DERIVATIONS. The part's two readings, each built as `106` builds its body, set against the lattice on every
  # density-matched PAIR of basis and rung — never against one rung: the ladder's own scatter is larger than several of
  # the differences, so a sign read off one rung was the defect two adversary rounds of 2026-10-21/22 found in turn.
  nu = sweep["poisson_ratio"]
  two = sweep["rows"].sort_by { |r| r["step_mm"] }.first(2)
  rich = ->(key, order) { two[0][key] + ((two[0][key] - two[1][key]) / (((two[1]["step_mm"] / two[0]["step_mm"])**order) - 1.0)) }
  body = lambda do |radial, axial|
    bulk = radial / ((1 + nu) * (1 - (2 * nu)))
    dev = ((3 * bulk) - Math.sqrt((9 * bulk * bulk) - (8 * bulk * axial))) / 2
    { axial:, bulk:, dev:, nu: (bulk - dev) / 2 / bulk }
  end
  # The part readings `105` takes (its first-order Richardson) are held to 105's OWN cache, not to this reimplementation.
  if File.exist?(CACHE_105)
    r105 = JSON.parse(File.read(CACHE_105)).dig("inputs", "fe_readings_richardson") || {}
    { "radial_richardson" => rich.call("radial_ratio", 1), "axial_richardson" => rich.call("axial_ratio", 1) }.each do |key, mine|
      failures << "105's cached #{key} #{r105[key].inspect} is not this layer's first-order Richardson #{mine} — the rule moved" unless r105[key] && (r105[key] - mine).abs < 1e-12
    end
  else
    failures << "105's cache is not committed — the part readings `105` takes have nothing to be held to"
  end
  equal16 = rung.call(16)
  matched = per["rows"].select { |r| (r["porosity"] - two[0]["porosity"]).abs < 0.005 }.sort_by { |r| r["steps_per_period"] }
  if matched.empty?
    failures << "no periodic rung sits within half a point of the part's porosity — canon's density-matched pairs have no rung"
  else
    # The rung RANGE canon quotes is read from canon and held to the density-matched set; no rung list lives here.
    lo_s = matched.first["steps_per_period"]
    hi_s = matched.last["steps_per_period"]
    inside = per["rows"].map { |r| r["steps_per_period"] }.select { |st| st.between?(lo_s, hi_s) }.sort
    failures << "the density-matched rungs #{matched.map { |r| r['steps_per_period'] }} are not one run of the ladder (#{inside}) — canon quotes them as a range" unless inside == matched.map { |r| r["steps_per_period"] }
    failures << "canon refuses /16 for its density; /16 is #{equal16['porosity']} against the part's #{two[0]['porosity']}" if (equal16["porosity"] - two[0]["porosity"]).abs < 0.005
    bases = [ body.call(rich.call("radial_ratio", 1), rich.call("axial_ratio", 1)), body.call(rich.call("radial_ratio", 2), rich.call("axial_ratio", 2)) ]
    pairs = bases.product(matched)
    dil_low = pairs.map { |pt, r| (1 - (pt[:bulk] / (r["C11"] + r["C12"]))) * 100 }
    dev_gap = pairs.map { |pt, r| ((pt[:dev] / (r["C11"] - r["C12"])) - 1) * 100 }
    axial_gap = pairs.map { |pt, r| ((pt[:axial] / r["E100"]) - 1) * 100 }
    shift16 = [ 1, 2 ].map { |o| ((rich.call("axial_ratio", o) / two[0]["axial_ratio"]) - 1).abs * 100 }
    mu_s = 1.0 / (2 * (1 + nu))
    field = ->(r, theta) { r["fields"].find { |x| (x["theta_deg"] - theta).abs < 1e-9 } || {} }
    pq = ->(r, theta, q) { field.call(r, theta).dig("principal_over_sigma_w", q) }
    band = ->(theta, q) { matched.map { |r| pq.call(r, theta, q) }.minmax }
    spread = ->(v) { (v.max / v.min) - 1 }
    plateau_rows = ladder["rows"].select { |r| r["cells_per_side"] >= 6 }
    plateau = plateau_rows.map { |r| r["axial_ratio"] }
    kp_fall = ->(r) { (1 - ((pq.call(r, 45.0, "p99") * Math.sqrt(field.call(r, 45.0)["modulus_ratio"])) / (pq.call(r, 0.0, "p99") * Math.sqrt(field.call(r, 0.0)["modulus_ratio"])))) * 100 }
    re_dil = /стійко розходиться в ньому ОДИН член — рівновісний розтяг у площині `C11 \+ C12`:\*\* на всіх парах «база × рунг» рівної густини він нижчий за матеріальний на (\d+)–(\d+) %, звідси й `ν\*` (\d+(?:\.\d+)?) проти (\d+(?:\.\d+)?)\./
    checks = [
      [ /порозність (\d+(?:\.\d+)?) % проти (\d+(?:\.\d+)?) % у деталі pine на період\/16/,
        [ finest["porosity"] * 100, two[0]["porosity"] * 100 ] ],
      [ /\*\*C44 — (\d+(?:\.\d+)?) стелі Фойгта/, [ finest["C44"] / (finest["solid_fraction_meshed"] * mu_s) ] ],
      [ /`A` ≈ (\d+(?:\.\d+)?), тобто/, [ finest["zener"] ] ],
      [ /`E\[110\]` ≈ (\d+(?:\.\d+)?)·`E\[100\]`/, [ finest["E110"] / finest["E100"] ] ],
      [ /її `E\[100\]` \((\d+(?:\.\d+)?)\) лежить усередині драбини з плитами без тертя на тому самому кроці \((\d+(?:\.\d+)?)–(\d+(?:\.\d+)?)\), на (\d+(?:\.\d+)?) % нижче її плато (\d+)–(\d+) комірок/,
        [ equal16["E100"], ladder["rows"].map { |r| r["axial_ratio"] }.min, ladder["rows"].map { |r| r["axial_ratio"] }.max,
          (1 - (equal16["E100"] / (plateau.sum / plateau.size))) * 100, *plateau_rows.map { |r| r["cells_per_side"] }.minmax ] ],
      [ /Осьове читання ДЕТАЛІ відносно `E\[100\]` ґратки — на всіх парах «база × рунг» рівної густини \(Річардсон 1-го й 2-го порядку деталі проти рунгів період\/(\d+)–\/(\d+)\) — від (−\d+(?:\.\d+)?) % до (\+\d+(?:\.\d+)?) %: деталь нижча на (\d+) парах із (\d+), але знака розриву драбина не встановлює\. Рівний крок базою не є: сира деталь на період\/16 ще не збіглась \(екстраполяція зсуває її осьове читання на (\d+)–(\d+) %\), а фазово-замкнений куб там на іншій густині \((\d+(?:\.\d+)?) % проти (\d+(?:\.\d+)?) %\)/,
        [ lo_s, hi_s, axial_gap.min, axial_gap.max, axial_gap.count(&:negative?), pairs.size, shift16.min, shift16.max,
          equal16["porosity"] * 100, two[0]["porosity"] * 100 ] ],
      [ re_dil, [ dil_low.min, dil_low.max, bases[0][:nu], finest["nu_star"] ] ],
      [ /Девіаторний член `C11 − C12` міняє знак від пари до пари: тіло вище за матеріальний на (\d+) парах із (\d+) \(від (−\d+(?:\.\d+)?) % до (\+\d+(?:\.\d+)?) %\), тож порядку жорсткості між двома тензорами вимір не встановлює/,
        [ dev_gap.count(&:positive?), pairs.size, dev_gap.min, dev_gap.max ] ],
      [ /На рунгах рівної густини \(період\/(\d+)–\/(\d+)\) p99 лежить у смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) на θ = 0 і (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) на θ = 45°, p99\.9 на θ = 0 — у смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?), а максимум не збігається \(на θ = 0 — (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?)\), тож прочитанням він не є/,
        [ lo_s, hi_s, *band.call(0.0, "p99"), *band.call(45.0, "p99"), *band.call(0.0, "p99.9"), *band.call(0.0, "max") ] ],
      [ /на кожному рунгу драбини він на 45° нижчий, ніж на 0°, а `√E` — вищий, тож добуток `k_p·√E` за p99 від 0° до 45° падає \(на рунгах рівної густини — на (\d+)–(\d+) %\)/,
        matched.map(&kp_fall).minmax ]
    ]
    checks.each do |re, values|
      m = canon.match(re)
      next failures << "periodic derivation /#{re.source[0, 60]}…/ is gone or reworded — fix its shape, do not drop it" if m.nil?

      periodic_anchors += 1
      m.captures.zip(values).each do |quoted, value|
        flag(failures, "periodic derivation «#{m[0][0, 70]}…»", render.call(value, quoted), quoted) if render.call(value, quoted) != quoted
      end
    end
    # The words the numbers stand under, held to the numbers — each word in a regex above, each claim here:
    lo, hi = ladder["rows"].map { |r| r["axial_ratio"] }.minmax
    failures << "periodic /16 E[100] #{equal16['E100']} is not inside the cube ladder #{lo}–#{hi}, as canon says" unless equal16["E100"].between?(lo, hi)
    failures << "«стійко … нижчий»: the in-plane dilatational term is not lower on every pair; #{dil_low}" unless dil_low.all?(&:positive?)
    failures << "«міняє знак»: the deviatoric gap keeps ONE sign over the pairs — canon must say which; #{dev_gap}" unless dev_gap.min.negative? && dev_gap.max.positive?
    failures << "«знака розриву драбина не встановлює»: the axial gap keeps ONE sign over the pairs — canon must say which; #{axial_gap}" unless axial_gap.min.negative? && axial_gap.max.positive?
    # ν* is quoted once per tensor and holds for every base and every density-matched rung — the quoted digits decide.
    if (mdil = canon.match(re_dil))
      failures << "canon quotes ν* #{mdil[3]} for the part body; the two bases give #{bases.map { |b| b[:nu] }}" unless bases.all? { |b| render.call(b[:nu], mdil[3]) == mdil[3] }
      failures << "canon quotes ν* #{mdil[4]} for the lattice; the density-matched rungs give #{matched.map { |r| r['nu_star'] }}" unless matched.all? { |r| render.call(r["nu_star"], mdil[4]) == mdil[4] }
    end
    failures << "«максимум не збігається»: its spread over the matched rungs is not wider than three times p99's" unless spread.call(matched.map { |r| pq.call(r, 0.0, "max") }) > 3 * spread.call(matched.map { |r| pq.call(r, 0.0, "p99") })
    failures << "«на кожному рунгу драбини … нижчий … вищий»: k_p does not fall and √E rise on every rung" unless per["rows"].all? { |r| pq.call(r, 45.0, "p99") < pq.call(r, 0.0, "p99") && field.call(r, 45.0)["modulus_ratio"] > field.call(r, 0.0)["modulus_ratio"] }
  end
else
  failures << "the periodic cache is not committed — canon §5.2 quotes it (`fea --periodic`)"
end

if failures.empty?
  puts "fea_canon_sync ✓ — 01_01 §5.2 matches tools/cad/cache/fea (transcription + #{anchors} derivation anchors + provenance " \
       "+ #{fit_rows_seen} fitted rows + #{dilation_rows_seen} sensitivity rows and #{dilation_anchors} of their derivations, " \
       "zero row = the pinned sweep field for field, + the graded pair of §5.5, + the canonical pair as quoted #{pair_quotes}× " \
       "and #{pair_derivations} derivations with it, + #{periodic_rows_seen} periodic-tensor rows and #{periodic_anchors} of " \
       "their derivations)"
  exit 0
end

warn "fea_canon_sync ✗ — canon §5.2 has drifted from the FE cache:"
failures.each { |f| warn "  · #{f}" }
warn "\nFix at the HOME (the cache is the measurement; canon quotes it) — re-run `dotnet run -- fea … --sweep`"
warn "and `fea --ladder` if the geometry moved, or correct the canon sentence if only the prose drifted."
exit 1
