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
# WHAT IT CHECKS — FIVE layers, in increasing distance from the raw data (⚠️ this line said "three"
# for the hours between the fourth landing and this correction — a header is a claim about its own file,
# and the edit that falsifies it is one section below, where nothing looks at the header):
#   1. TRANSCRIPTION — every cell of the two canon tables against the cached rows.
#   2. DERIVATION — the figures canon computes FROM those rows (Gibson-Ashby at the measured density,
#      the two ratios to it, GPa at the reference solid modulus, the single-point readings, the spread).
#      This is the layer that catches a correct cache quoted into a wrong sentence.
#   3. PROVENANCE — that the cache still describes the run canon claims (SKU, topology, rod excluded).
#   4. THE FITTED TABLE — the measured Gibson-Ashby C/n against the per-resolution `gibson_ashby_fit.*`
#      family, which layers 1-3 do not read at all, plus that family's own provenance (specimen size).
#   5. THE FACE-OFFSET SENSITIVITY TABLE — each row against its per-row `dilation_sensitivity.*` file, and
#      the zero row against the pinned step sweep FIELD FOR FIELD, which is the identity control itself.
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
  "деталь (кільцева зона Ø11×40)" =>
    { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d" },
  "деталь (кільцева зона Ø11×40, знесена гілка)" =>
    { glob: "tools/cad/cache/fea/gibson_ashby_fit.anchor_zone1_pine.d%<n>d.json", label: "період/%<n>d", retired: true }
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
  # fits were measured on — an annulus around a Ø1.35 channel — cannot be produced by any verb in this tree
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
                "`with_bus_rod` fingerprint — it was re-measured on the welded body, so DROP «знесена гілка» from "\
                "the specimen cell (and from FIT_ROWS) instead of leaving canon under-claiming a fresh number"
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
#       body, rod-free, network, converged — and it calls itself a SENSITIVITY, never the printed body;
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

EXPECTED_ANCHORS = 8
if anchors < EXPECTED_ANCHORS
  failures << "only #{anchors} of #{EXPECTED_ANCHORS} derivation anchors matched — a canon rewording has "\
              "DISARMED a comparison; find the reworded sentence, do not lower this number"
end

if failures.empty?
  puts "fea_canon_sync ✓ — 01_01 §5.2 matches tools/cad/cache/fea (transcription + #{anchors} derivation anchors + provenance " \
       "+ #{fit_rows_seen} fitted rows + #{dilation_rows_seen} sensitivity rows and #{dilation_anchors} of their derivations, " \
       "zero row = the pinned sweep field for field)"
  exit 0
end

warn "fea_canon_sync ✗ — canon §5.2 has drifted from the FE cache:"
failures.each { |f| warn "  · #{f}" }
warn "\nFix at the HOME (the cache is the measurement; canon quotes it) — re-run `dotnet run -- fea … --sweep`"
warn "and `fea --ladder` if the geometry moved, or correct the canon sentence if only the prose drifted."
exit 1
