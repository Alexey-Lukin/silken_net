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
#      the two ratios to it, GPa at the reference solid modulus, the reduction factors, the gap to the wood's
#      transverse modulus in §5.1 and §5.2, the
#      single-point readings, the spread). This is the layer that catches a correct cache quoted into a wrong sentence.
#   3. PROVENANCE — that the cache still describes the run canon claims (SKU, topology, rod excluded).
#   4. THE FITTED TABLE — the measured Gibson-Ashby C/n against the per-resolution `gibson_ashby_fit.*`
#      family, which layers 1-3 do not read at all, plus that family's own provenance (specimen size);
#      4b. the prose that READS that table — the equal-step gap and its two conditions, the cube's band, the older
#      verdict paragraph, the fit commands, and the Richardson caveat under the step sweep.
#   5. THE FACE-OFFSET SENSITIVITY TABLE — each row against its per-row `dilation_sensitivity.*` file, and
#      the zero row against the pinned step sweep FIELD FOR FIELD, which is the identity control itself.
#   6. THE GRADED-POROSITY PAIR (§5.5) — graded part against its uniform twin at equal mass, recomputed from
#      two cache families by the same log-log interpolation canon describes.
#   7. THE CANONICAL PAIR (§5.2/§5.5) — the ratified lattice · axial · `/32` C/n wherever canon states it in prose,
#      and the two E figures canon computes with it, re-derived at the tolerance each input actually carries.
#   8. THE PERIODIC TENSOR AND FIELD (§5.2, HW.23) — the effective-tensor ladder and the field-quantile rows against
#      `periodic_homogenization.*`, that file's provenance and controls, and every sentence canon derives from it —
#      including the one that sets it beside the PART's two readings, recomputed by `105`'s own Richardson rule.
#   9. THE STEP LADDER (§5.2, HW.23) — the merged sweep ⊕ re-sweep table with its lock flags and the sentences derived
#      from it (the unlocked chain's convergence, the locked rows' cost, the two readings `105` takes).
#  10. THE STATIC IN-PLANE READING (§5.2, HW.23) — the traction table against `<cem>.traction.h*um.json`, those files'
#      provenance and controls, the set of steps, and the sentences canon derives from them against `105`'s two readings.
#
# ⚠️ DECLARED CEILING, and it is wider than the usual one for a value guard:
#   • It judges NUMBERS — and, in 4b and 8, the derivations prose computes from them with the words those stand
#     on — never the reasoning around them. A row can match perfectly under a sentence that
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

# ── The merged STEP LADDER: the pinned sweep (steps = axial period / N) + the HW.23 re-sweep (`--step-mm` rows, one file
#    each, 2026-10-23), one row per step, coarse → fine, each flagged LOCKED when its step divides the part's axial period
#    (since HW.33 (в) the rim's, one for the whole part — picogk gotcha #16). The same rule 105's `read_fe` applies; the
#    headline reading of §5.2 is the finest UNLOCKED row (the converged one), the finest LOCKED row the bracket's other end.
RIM_PERIOD_MM = JSON.parse(File.read(File.join(ROOT, "tools/cad/cem/anchor_zone1.pine.json")))["gyroid_period_rim_mm"]
fine_files = Dir[File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.h*um.json")].sort
h_rows = fine_files.flat_map do |f|
  d = JSON.parse(File.read(f))
  failures << "#{File.basename(f)} is not the sweep's specimen (#{d['cem']} · #{d['topology']})" unless d["cem"] == sweep["cem"] && d["topology"] == sweep["topology"]
  failures << "#{File.basename(f)}: the FE's ν differs from the sweep's" unless (d["poisson_ratio"] - sweep["poisson_ratio"]).abs < 1e-12
  d["rows"].map { |r| r.merge("source" => File.basename(f)) }
end
step_ladder = (sweep["rows"].map { |r| r.merge("source" => "sweep") } + h_rows).group_by { |r| r["step_mm"].round(9) }.map do |step, rs|
  # the identity control: a step both families carry (the re-sweep's /8) must agree field for field, or the re-sweep is
  # not the sweep's instrument
  rs.drop(1).each do |r|
    %w[elements porosity axial_ratio radial_ratio].each do |k|
      failures << "step #{step} mm: #{r['source']} disagrees with the pinned sweep on #{k} (#{r[k]} vs #{rs.first[k]})" if (r[k] - rs.first[k]).abs > 1e-9 * [ 1.0, r[k].abs ].max
    end
  end
  rs.first
end.sort_by { |r| -r["step_mm"] }
# the mirror of VoxelFea.RepeatCells (its ONE home; 105's `axial_lock_cells` is the other mirror): the sampled phase repeats
# within ≤ 4 axial cells at tolerance 1e-4·cells — the steps are float32, so `/24` sits 7.7e-7 off an integer count
axial_lock_cells = lambda do |step_mm|
  per = RIM_PERIOD_MM / step_mm
  (1..4).find { |cells| ((per * cells) - (per * cells).round).abs < 1e-4 * cells } || 0
end
step_ladder.each do |r|
  r["locked"] = axial_lock_cells.call(r["step_mm"]).positive?
  failures << "step #{r['step_mm']} mm (#{r['source']}) did not converge — canon must not quote it" unless r["converged"]
end
unlocked_rows = step_ladder.reject { |r| r["locked"] }
locked_rows = step_ladder.select { |r| r["locked"] }
failures << "the step ladder has no unlocked step — the HW.23 re-sweep (`anchor_zone1_pine.h*um.json`) is not in cache/fea" if unlocked_rows.empty?
finest_unlocked = unlocked_rows.last || sweep["rows"].min_by { |r| r["step_mm"] }
finest_locked = locked_rows.last
# per axis the ADVERSE (lower) end of the [finest unlocked ⊥ finest locked] bracket — 105's binding reading
part_reading = %w[radial axial].to_h { |ax| [ ax, [ finest_unlocked["#{ax}_ratio"], finest_locked["#{ax}_ratio"] ].min ] }

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
# `finest` is the CONVERGED reading — the finest UNLOCKED row of the merged step ladder (HW.23, 2026-10-23), not the
# pinned sweep's /16, which is phase-locked and sits under it (layer 8 reads that row as `two[0]` where a sentence names it).
finest = finest_unlocked
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

# The converged-reading row of the sweep table (it replaced the Richardson row 2026-10-23: the two-point extrapolation
# from /12 and /16 extrapolated a phase-locked error — HW.23) — the finest unlocked step, its 11/(2k) label and its
# step, the finest locked divisor, and both axes' bracket ends at the table's precision.
if (m = canon.match(/\| дужка найдрібніших кроків HW\.23 \(незамкнений 11\/(\d+) · ([0-9.]+) мм ⊥ замкнений `\/(\d+)`; збіжне прочитання — перший член, прочитання `105` — нижчий\) \| ([0-9.]+) ⊥ ([0-9.]+) \| ([0-9.]+) ⊥ ([0-9.]+) \|/))
  anchors += 1
  want = [ (11.0 / finest_unlocked["step_mm"]).round, finest_unlocked["step_mm"], (RIM_PERIOD_MM / finest_locked["step_mm"]).round,
           finest_unlocked["axial_ratio"], finest_locked["axial_ratio"], finest_unlocked["radial_ratio"], finest_locked["radial_ratio"] ]
  m.captures.zip(want).each_with_index do |(q, v), i|
    rendered = i < 3 && !q.include?(".") ? v.round.to_s : format("%.#{q.include?('.') ? q.split('.').last.length : 0}f", v)
    flag(failures, "converged-reading row of the sweep table [#{i}]", rendered, q) if rendered != q
  end
else
  failures << "the sweep table's «дужка найдрібніших кроків HW.23 (…)» row is gone or reworded — fix its shape, do not drop it"
end
# The lock cost at the finest locked step — the alloy table's limit (3) — both axes, from the bracket.
if (m = canon.match(/замкнений `\/(\d+)` лежить на ([0-9.]+) % нижче радіально й на ([0-9.]+) % вище осьово/))
  anchors += 1
  want = [ (RIM_PERIOD_MM / finest_locked["step_mm"]).round, (1 - (finest_locked["radial_ratio"] / finest_unlocked["radial_ratio"])) * 100,
           ((finest_locked["axial_ratio"] / finest_unlocked["axial_ratio"]) - 1) * 100 ]
  failures << "limit (3): canon names /#{m[1]}, the finest locked step is /#{want[0]}" if m[1].to_i != want[0]
  failures << "limit (3): the locked row is not under the unlocked one radially and over it axially (#{want[1]} · #{want[2]})" unless want[1].positive? && want[2].positive?
  [ [ want[1], m[2] ], [ want[2], m[3] ] ].each { |v, q| flag(failures, "limit (3) lock cost", format("%.#{q.split('.').last.length}f", v), q) if format("%.#{q.split('.').last.length}f", v) != q }
else
  failures << "the alloy table's limit (3) «замкнений `/N` лежить на X % нижче радіально й на Y % вище осьово» is gone or reworded — fix its shape"
end

# The gap to the wood's TRANSVERSE modulus — the live verdict figure of §5.1 ⛔, and it reads the finest RADIAL row. UNPINNED
# until 2026-10-22: the HW.33 re-measurement moved §5.2 to ~7–20× while §5.1 went on quoting the pre-verdict ~5–15×, and
# mutating either passed (RA1 review of b8bbf08fb). The wood band is read from the sentence that states it, never typed here;
# each end of the gap is the GPa over the band's OPPOSITE end. ⛔ The pre-verdict figures beside them are dated record — the
# sweep they came from is not in the tree, so nothing here holds them.
wood_gap = ->(gpa, band) { [ gpa / band[1], gpa / band[0] ] }
radial_gpa = finest["radial_ratio"] * E_SOLID_GPA
if (m = canon.match(/Розрив із поперечним модулем деревини `E_R`\/`E_T` ≈ (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) ГПа — \*\*~(\d+)–(\d+)×\*\* проти формульних ~(\d+)–(\d+)×/))
  anchors += 1
  wood_band = [ m[1].to_f, m[2].to_f ]
  want = wood_gap.call(radial_gpa, wood_band) + wood_gap.call(ga_part * E_SOLID_GPA, wood_band)
  m.captures.drop(2).zip(want).each { |q, v| flag(failures, "§5.2 gap to the wood's transverse modulus", format("%.0f", v), q) if format("%.0f", v) != q }
end
if (m = canon.match(/де `E_R`\/`E_T` ≈ (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) ГПа[^\n]*?звужує розрив до \*\*~(\d+)–(\d+)×\*\* \(до гео-присуду HW\.33 ~\d+–\d+×\)/))
  anchors += 1
  m.captures.drop(2).zip(wood_gap.call(radial_gpa, [ m[1].to_f, m[2].to_f ])).each do |q, v|
    flag(failures, "§5.1 gap to the wood's transverse modulus", format("%.0f", v), q) if format("%.0f", v) != q
  end
end
# The reduction factors of the §5.2 table — the reciprocal of the finest row, unpinned until the same review.
if (m = canon.match(/\*\*виміряно (\d+(?:\.\d+)?)× осьово · (\d+(?:\.\d+)?)× радіально\*\*/))
  anchors += 1
  m.captures.zip([ 1.0 / finest["axial_ratio"], 1.0 / finest["radial_ratio"] ]).each do |q, v|
    shown = format("%.#{q.include?('.') ? q.split('.').last.length : 0}f", v)
    flag(failures, "reduction factor (1 / the finest row)", shown, q) if shown != q
  end
end
# ── The WITH-ROD run: the RECORD of a branch that no longer exists. ──────────────────────────────
# ⚠️ Pinned rather than left to prose because it is the number a reader reaches for when they say "the
# part": the printed rod moved the axial figure by ~9 % and the radial by nothing.
# 🔴 Since 2026-09-18 BOTH sides of that comparison are FROZEN EVIDENCE, not live measurements: the
# welded branch removed the printed core from the anode and `fea --with-rod` with it (00_07 HW.1), so
# neither the with-rod row nor the annulus baseline it is quoted against can be re-measured by any verb
# in this tree. The baseline therefore reads from the FROZEN pre-A sweep, never from the live one — a
# comparison against today's sweep would be two different specimens wearing one sentence.
# ⚠️ Both records stay byte-frozen, so their `_note` still says «a single row is an UPPER bound, read the sweep» —
# RETRACTED 2026-10-22 (the instrument ceiling in VoxelFea.cs and 01_01 §5.2: the element error is one-signed only
# within one run, and the staircase shows no sign); the correction lives here and in canon, never in the records.
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

# ⛔ DECLARED CEILING (geometry eras): no fit cache records the generator's PHASE rule, so a geometry verdict leaves a
# part fit and its canon row self-consistent and green. The HW.33 (в) verdict (2026-10-22) was bridged by a row
# marker tied to the pre-verdict fitted C and retired with the last re-run (2026-10-23); the next verdict needs one again.

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

# ── 4b. THE SIZE-GAP PROSE (§5.2, HW.33) ─────────────────────────────────────────────────────────
#
# 🔴 Added 2026-10-22: the paragraphs that READ the fitted table — the equal-step gap and every copy of it, the two
# premises under which it is an upper estimate, the cube's band, the part's ladder, the exponent agreement, the older
# verdict paragraph and the fit command — carried arithmetic no layer held, and two figures had sat wrong since
# 2026-09-16 and 09-18: «±0.6 %» for a band 0.7 % wide, and «в межах ±0.6 %» for +0.69 %. Held: every number those
# sentences compute from fit caches still in the tree, at the steps the sentence NAMES — a historical figure is looked up
# by the step it states, never by its position in the table — the equal step too is the one the gap sentence names — so
# a correct new rung reds nothing that is still true; and the words they stand on (one row for the condition and the
# gap, one step for both specimens, the band narrower than the gap's size, the post-HW.33 sweep
# not monotone on either axis with the fits read at the nominal wall inside that saw, the part's fitted-C chain non-monotone
# as canon states it, the gap SIGNED — it changed sign with the HW.33 (в) geometry — and every printed fit command carrying its
# cache's walls). A one-sided bound («в межах X %») is held to the smallest X at its
# precision that keeps it true; a range DERIVED from the rows («на X–Y %») is rounded OUTWARD, so it contains the
# measured one; a range of the table's own cells («у смузі 2.198–2.320») is quoted at the table's precision, as the
# reader sees the cells — rounding a derived figure to nearest is what let «±0.6 %» stand for +0.69 %.
# ⛔ DECLARED CEILING: not the retired annulus's figures (1.033, +5.1 %, 2.2387, +8.8 %, the per-step falls of the ⊕) nor
# the pre-HW.33 body's (1.025, +4.3 %, 2.2400, 0.0015, 1.155 → 1.046 → 1.025; its «зійшов із +5.1 % до +4.3 %» check was
# retired with them 2026-10-23) — the re-measurements overwrote their caches, so they stand as dated record; not
# «40 кроках проти 32» (CEM periods); not the mirrors of §5.2 in SUMMARY, the skills and the tracker — since 2026-10-23
# they carry the direction in words and no number of their own;
# not the run times («8 год 20 хв» — no cache records a duration; the COST power is held, from elements × CG
# iterations); not «той самий прилад» — that the sweep and the part fits share the sampler, the solver and the step
# rule is a fact of Program.cs this gate cannot read; and the part's E at the nominal wall is READ OFF its fits by a
# cubic through the four walls nearest it — an interpolation, held here as the reading canon quotes, not as a
# measurement at that wall.
gap_anchors = 0
gap_render = ->(value, quoted) { format("%#{quoted.start_with?('+') ? '+' : ''}.#{quoted.include?('.') ? quoted.split('.').last.length : 0}f", value).sub(/\A-/, "−") }
# The smallest bound at the quoted precision that is not below the value — a one-sided «в межах X %» is true only then.
gap_ceil = lambda do |value, quoted|
  digits = quoted.include?(".") ? quoted.split(".").last.length : 0
  # The 1e-9 keeps a value sitting ON a quoted boundary (0.7 → 7.000000000000001 in binary) from rounding a step up.
  format("%.#{digits}f", ((value * (10**digits)) - 1e-9).ceil.fdiv(10**digits))
end
apostrophe = ->(word) { word.to_s.tr("'’", "ʼʼ") }
# The cubic through the four walls nearest x0 (Lagrange) — an INTERPOLATION: it passes through every row it reads, which
# the least-squares cubic over all six that stood here first did not (it missed measured rows by up to 0.95 %).
# ⚠️ A top-level lambda SHARES the file's locals: that cubic's matrix was named `m` and overwrote the MatchData the
# Richardson check was reading. Every name assigned below is one no outer scope holds.
cubic_at = lambda do |xs, ys, x0|
  near = xs.each_index.min_by(4) { |i| (xs[i] - x0).abs }
  near.sum { |i| ys[i] * near.reduce(1.0) { |acc, j| j == i ? acc : acc * (x0 - xs[j]) / (xs[i] - xs[j]) } }
end
fit_ladder = lambda do |specimen|
  canon.scan(/^\| \*{0,2}#{Regexp.escape(specimen)}\*{0,2} \| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}осьова\*{0,2} \|/)
       .flatten.map(&:to_i).uniq.sort.filter_map do |div|
    path = File.join(ROOT, format(FIT_ROWS[specimen][:glob], n: div))
    next unless File.exist?(path)

    f = JSON.parse(File.read(path))
    step = f["step_mm"] || (f["period_mm"] && f["steps_per_period"] && (f["period_mm"].to_f / f["steps_per_period"]))
    [ div, { c: f["fit_c"] || f["fit_axial_c"], n: f["fit_n"] || f["fit_axial_n"], rc: f["fit_radial_c"], step_mm: step, rows: f["rows"] } ]
  end.to_h
end
chain = ->(text) { text.split(" → ").map { |x| x.delete("*") } }
cube_fit = fit_ladder.call("ґратка (куб 2 комірки)")
part_fit = fit_ladder.call("деталь (ґратка до осі Ø11×40)")
if cube_fit.size < 3 || part_fit.size < 2
  failures << "size-gap prose: canon's fit table yields #{cube_fit.size} cube and #{part_fit.size} part axial rows — the paragraphs need three and two"
else
  finest3 = cube_fit.keys.last(3)
  low_div = finest3.min_by { |d| cube_fit[d][:c] }
  shared = part_fit.keys & cube_fit.keys
  # The equal step is the one the gap sentence NAMES («при рівному кроці X мм»), never the finest shared one by
  # position: a correct finer part rung beside the cube's /64 would otherwise move the gap under a sentence still at /32.
  eq_quote = canon[/`C` же не зійшовся: при рівному кроці (\d+(?:\.\d+)?) мм/, 1]
  eq_div = eq_quote && shared.select { |d| gap_render.call(part_fit[d][:step_mm], eq_quote) == eq_quote }.min_by { |d| (part_fit[d][:step_mm] - eq_quote.to_f).abs }
  if eq_div.nil?
    failures << "size-gap: «при рівному кроці X мм» is gone, or names no step that carries both a part and a cube fit row (quoted: #{eq_quote.inspect})"
  else
    gap = ((part_fit[eq_div][:c] / cube_fit[eq_div][:c]) - 1) * 100
    band = finest3.map { |d| cube_fit[d][:c] }.minmax
    spread = ((band.max / band.min) - 1) * 100
    part_c = part_fit.values.map { |v| v[:c] }
    count_word = { 3 => "трьох", 4 => "чотирьох", 5 => "пʼяти", 6 => "шести", 7 => "семи", 8 => "восьми" }
    failures << "«при рівному кроці»: the part's /#{eq_div} step is #{part_fit[eq_div][:step_mm]} mm, the cube's /#{eq_div} #{cube_fit[eq_div][:step_mm]} mm" unless part_fit[eq_div][:step_mm] && cube_fit[eq_div][:step_mm] && (part_fit[eq_div][:step_mm] - cube_fit[eq_div][:step_mm]).abs < 1e-6
    failures << "«Перша умова … найнижчий у смузі, тож проти будь-якого з трьох розрив не менший»: the band's lowest row is /#{low_div}, the gap is taken at /#{eq_div} — the condition and the gap must name ONE row" unless low_div == eq_div
    # The gap is SIGNED (it changed sign with the HW.33 (в) geometry, 2026-10-23); the band is compared to its size.
    # The sentence is the carrier: its words name the comparison (the band against the gap's SIZE, no literal threshold).
    if canon.include?("і руху на величину розриву там немає — на незбіжність куба залишок не списується")
      gap_anchors += 1
      failures << "«руху на величину розриву там немає — на незбіжність куба залишок не списується»: the cube's three finest rows spread #{spread} % against a #{gap} % gap" unless spread < gap.abs
    else
      failures << "size-gap: «і руху на величину розриву там немає — на незбіжність куба залишок не списується» is gone or reworded — fix its shape"
    end
    # ── Every SIGN, DIRECTION and SHAPE word is a CAPTURE derived from the caches (guard-craft #186): a flip reds as a
    #    wrong word («canon says X, cache gives Y»), never as «gone or reworded». The facts the words stand on:
    incs = part_c.each_cons(2).map { |x, y| y - x }
    falling = incs.all?(&:negative?)
    rising = incs.all?(&:positive?)
    shape = falling ? "СПАДНА" : rising ? "ЗРОСТАЄ" : "НЕ монотонна"
    band_narrow = spread < gap.abs
    cond2 = falling ? "підтримує" : rising ? "спростовує" : "не судить"
    supports_word = if band_narrow && falling then "обидві"
    elsif band_narrow then "лише першу"
    elsif falling then "лише другу"
    else "жодної"
    end
    # The flip sentence quotes the PRE-verdict C and gap (a dated record): the gap is re-derived from that C against the
    # cube row that IS in the tree, so the record cannot be edited into a coherent falsehood; the signs decide the verb.
    old_gap = nil
    if (sm = canon.match(/і знак розриву гео-присуд (ПЕРЕВЕРНУВ|ЗБЕРІГ):\*\* на тілі до присуду деталь була (жорсткішою|мʼякшою) за куб у підігнаному `C` \((\d+\.\d+), ([+−]\d+\.\d+) %;/))
      gap_anchors += 1
      old_c = sm[3].to_f
      old_gap = sm[4].tr("−", "-").to_f
      flag(failures, "size-gap: the quoted pre-verdict gap against the quoted pre-verdict C and the cube's /#{eq_div}", gap_render.call(((old_c / cube_fit[eq_div][:c]) - 1) * 100, sm[4]), sm[4]) if gap_render.call(((old_c / cube_fit[eq_div][:c]) - 1) * 100, sm[4]) != sm[4]
      verb = old_gap.negative? == gap.negative? ? "ЗБЕРІГ" : "ПЕРЕВЕРНУВ"
      was = old_gap.positive? ? "жорсткішою" : "мʼякшою"
      flag(failures, "size-gap «ПЕРЕВЕРНУВ/ЗБЕРІГ»", verb, sm[1]) if sm[1] != verb
      flag(failures, "size-gap «була жорсткішою/мʼякшою»", was, sm[2]) if sm[2] != was
    else
      failures << "size-gap: the sign-flip sentence «і знак розриву гео-присуд … на тілі до присуду деталь була … (C, ±gap %;» is gone or reworded — fix its shape"
    end
    prev_div = part_fit.keys.select { |d| d < eq_div }.max
    step_dir = prev_div && (part_fit[eq_div][:c] > part_fit[prev_div][:c] ? "угору" : "вниз")
    closer = prev_div && ((part_fit[eq_div][:c] - cube_fit[eq_div][:c]).abs < (part_fit[prev_div][:c] - cube_fit[eq_div][:c]).abs ? "ближче до куба" : "далі від куба")
    was_under = prev_div && part_fit[prev_div][:c] < cube_fit[eq_div][:c]
    is_under = part_fit[eq_div][:c] < cube_fit[eq_div][:c]
    stands = is_under ? (was_under ? "але й далі під ним" : "і вже під ним") : (was_under ? "і вже над ним" : "але й далі над ним")
    word_checks = {
      "«тож проти будь-якого з трьох розрив не менший/не більший»" => [ /найнижчий у смузі, тож проти будь-якого з трьох розрив (не менший|не більший)/, gap.negative? ? "не менший" : "не більший" ],
      "«межа під смугою зменшила б/підняла б розрив»" => [ /а межа під смугою (зменшила б|підняла б) розрив/, gap.negative? ? "зменшила б" : "підняла б" ],
      "«на відвантажуваній — мʼякша/жорсткіша»" => [ /на відвантажуваній — (мʼякша|жорсткіша), і її `C`/, gap.negative? ? "мʼякша" : "жорсткіша" ],
      "«тобто нижня/верхня оцінка його величини»" => [ /ПІДПИСАНОГО розриву, тобто (нижня|верхня) оцінка його величини/, gap.negative? ? "нижня" : "верхня" ],
      "«і вимір підтримує лише першу/лише другу/обидві/жодної»" => [ /оцінка його величини, і вимір підтримує (лише першу|лише другу|обидві|жодної)\*\*/, supports_word ],
      "«зміряно відʼємним/додатним»" => [ /рівнокроковий розрив нової геометрії зміряно (відʼємним|додатним) — \*\*/, gap.negative? ? "відʼємним" : "додатним" ],
      "«протилежного/того самого знака до тіла до присуду»" => [ /при рівному кроці виміряно [+−]\d+(?:\.\d+)? %, (протилежного|того самого) знака до тіла до присуду/, old_gap && (old_gap.negative? == gap.negative? ? "того самого" : "протилежного") ],
      "«нижньою/верхньою оцінкою величини розриву»" => [ /знака до тіла до присуду; (нижньою|верхньою) оцінкою величини розриву/, gap.negative? ? "нижньою" : "верхньою" ],
      "«вимір підтримує/не підтримує (1)»" => [ /з яких вимір (підтримує|не підтримує) \(1\) і/, band_narrow ? "підтримує" : "не підтримує" ],
      "«і підтримує/не судить/спростовує (2)»" => [ /\(1\) і (підтримує|не судить|спростовує) \(2\)/, cond2 ],
      "«драбинка підігнаного C НЕ монотонна/СПАДНА/ЗРОСТАЄ»" => [ /драбинка підігнаного `C` (НЕ монотонна|СПАДНА|ЗРОСТАЄ):\*\* після гео-присуду/, shape ],
      "«спад/підйом на першому кроці»" => [ /\(прирости [^)]*\) — (спад|підйом) на першому кроці й/, incs[0] && (incs[0].negative? ? "спад" : "підйом") ],
      "«й спад/підйом на другому»" => [ /на першому кроці й (спад|підйом) на другому, менший за ширину смуги куба/, incs[1] && (incs[1].negative? ? "спад" : "підйом") ],
      "«повернув його … угору/вниз»" => [ /повернув його на \d+\.\d+ % (угору|вниз), до/, step_dir ],
      "«ближче до куба/далі від куба»" => [ /, до \d+\.\d+ — (ближче до куба|далі від куба), /, closer ],
      "«але й далі під ним/і вже над ним/…»" => [ /— (?:ближче до куба|далі від куба), (але й далі під ним|і вже над ним|але й далі над ним|і вже під ним):/, stands ]
    }
    word_checks.each do |label, (re, want)|
      sm = canon.match(re)
      next failures << "size-gap: #{label} is gone or reworded — fix its shape" if sm.nil?

      gap_anchors += 1
      next failures << "size-gap: #{label} cannot be derived (a fact it stands on is missing from the caches or the flip sentence)" if want.nil?

      flag(failures, "size-gap #{label}", want, sm[1]) if sm[1] != want
    end
    # The ratified pair's confirming row — a ONE-SIDED bound, both steps read from the sentence.
    if (m = canon.match(/Канонна пара — ґратка · осьова · `\/(\d+)`: [^(]*\(РАТИФІКОВАНО founder 2026-09-18, [^;]*; рядок `\/(\d+)` підтверджує її в межах (\d+(?:\.\d+)?) % по `C`\)/))
      gap_anchors += 1
      pair = m[1].to_i
      confirm = m[2].to_i
      if cube_fit.key?(pair) && cube_fit.key?(confirm)
        moved = ((cube_fit[confirm][:c] / cube_fit[pair][:c]) - 1).abs * 100
        flag(failures, "size-gap «рядок /#{confirm} підтверджує її в межах … по C» (one-sided, held to the smallest true bound)", gap_ceil.call(moved, m[3]), m[3]) if gap_ceil.call(moved, m[3]) != m[3]
      else
        failures << "size-gap: the ratified pair names /#{pair} and /#{confirm}, and the cube table has no such row"
      end
    else
      failures << "size-gap: the ratified pair's «рядок /N підтверджує її в межах … % по C» is gone or reworded — fix its shape"
    end
    finest_part = part_fit.keys.last
    finest_cube = cube_fit.keys.last
    single_c = ->(d, w) { r = cube_fit.dig(d, :rows)&.find { |x| (x["wall_param"] - w).abs < 1e-6 }; r && (r["axial_ratio"] / (r["relative_density"]**2)) }
    # The table as the reader SEES it: a band of its cells must not contradict them at face value («2.20» beside a cell
    # «2.198»), so each band end is held to the displayed cell of its extreme row, not merely to the value at some precision.
    shown = canon.scan(/^\| \*{0,2}(ґратка \(куб 2 комірки\)|деталь \(ґратка до осі Ø11×40\))\*{0,2} \| \*{0,2}період\/(\d+)\*{0,2} \| \*{0,2}осьова\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|/)
                 .to_h { |sp, d, c, n| [ [ sp.start_with?("ґратка") ? :cube : :part, d.to_i ], { c: c, n: n } ] }
    n_lo_cell, n_hi_cell = (cube_fit.map { |d, v| [ [ :cube, d ], v[:n] ] } + part_fit.map { |d, v| [ [ :part, d ], v[:n] ] })
                           .minmax_by(&:last).map { |key, _| shown.dig(key, :n) }
    all_n = cube_fit.values.map { |v| v[:n] } + part_fit.values.map { |v| v[:n] }
    # An entry's values may be a lambda over its own match: a historical sentence is then held at the steps it NAMES,
    # never at a position in the table, so a correct new rung — coarser, finer or between — reds nothing still true.
    checks = [
      [ /На найдрібніших рядках обох зразків `n` розходиться лише на \*\*(\d+(?:\.\d+)?)\*\* \((\d+(?:\.\d+)?) деталь · (\d+(?:\.\d+)?) куб;/,
        [ (part_fit[finest_part][:n] - cube_fit[finest_cube][:n]).abs, part_fit[finest_part][:n], cube_fit[finest_cube][:n] ] ],
      [ /`C` же не зійшовся: при рівному кроці (\d+(?:\.\d+)?) мм деталь дає \*\*(\d+(?:\.\d+)?)\*\* проти (\d+(?:\.\d+)?) у куба — \*\*([+−]\d+(?:\.\d+)?) %\*\*/,
        [ part_fit[eq_div][:step_mm], part_fit[eq_div][:c], cube_fit[eq_div][:c], gap ] ],
      [ /⚠️ \*\*([+−]\d+(?:\.\d+)?) % — за двох умов це верхня оцінка ПІДПИСАНОГО розриву, тобто (?:нижня|верхня) оцінка його величини, і вимір підтримує (?:лише першу|лише другу|обидві|жодної)\*\*/, [ gap ] ],
      [ /рівнокроковий розрив нової геометрії зміряно (?:відʼємним|додатним) — \*\*([+−]\d+(?:\.\d+)?) %\*\*/, [ gap ] ],
      # The last rung against the one before it, both against the cube's row at the equal step (the words — above).
      [ /а крок куба \(`\/(\d+)`, 2026-10-23\) повернув його на (\d+\.\d+) % (?:угору|вниз), до (\d+\.\d+) —/,
        ->(md) { d = md[1].to_i; prev = part_fit.keys.select { |k| k < d }.max; [ (d if d == eq_div), (prev && ((part_fit[d][:c] / part_fit[prev][:c]) - 1).abs * 100), part_fit.dig(d, :c) ] } ],
      # The between-geometry shifts: the OLD values are a dated record quoted at four decimals, the NEW ones are the
      # tree's, and each percentage is re-derived from the quoted old value and the cache.
      [ /рушив на (\d+\.\d+) % \((\d+\.\d+) → (\d+\.\d+)\), `C` — на (\d+\.\d+) % \((\d+\.\d+) → (\d+\.\d+)\)/,
        ->(md) { on, oc = md[2].to_f, md[5].to_f; f = part_fit[finest_part]; [ ((f[:n] / on) - 1).abs * 100, on, f[:n], ((f[:c] / oc) - 1).abs * 100, oc, f[:c] ] } ],
      # «32 кроки на обідний період»: the rim period of the pine manifest over the finest part fit's step.
      [ /\((\d+) кроки на обідний період\)/,
        ->(_md) { rim = JSON.parse(File.read(File.join(ROOT, "tools/cad/cem/anchor_zone1.pine.json")))["gyroid_period_rim_mm"]; [ (rim / part_fit[finest_part][:step_mm]).round ] } ],
      # The part's /32 C against the whole cube table — the «нижче за всі чотири рядки куба» clause, at the table's precision.
      [ /її `C` на `\/(\d+)` лежить нижче за всі чотири рядки куба \((\d+\.\d+)–(\d+\.\d+)\)/,
        ->(md) { cs = cube_fit.values.map { |v| v[:c] }; ok = cube_fit.size == 4 && part_fit.dig(md[1].to_i, :c).to_f < cs.min; [ (md[1].to_i if ok), cs.min, cs.max ] } ],
      [ /\*\*Перша умова — межа куба не нижча за його рядок `\/(\d+)`\*\*, найнижчий у смузі/, [ low_div ] ],
      [ /\*\*Друга умова — межа деталі не вища за її рядок `\/(\d+)`\*\* — її підтримала б спадна драбинка/, [ eq_div ] ],
      [ /🔑 \*\*Отже чесне прочитання: при рівному кроці виміряно ([+−]\d+(?:\.\d+)?) %, (?:протилежного|того самого) знака до тіла до присуду; (?:нижньою|верхньою) оцінкою величини розриву він є лише за умов \(1\) і \(2\)/, [ gap ] ],
      [ /Найдрібніший рядок виміряно на \*\*КУБІ\*\* \(`\/(\d+)` — матеріальний масштаб, який формула й описує\), найдрібніший рядок деталі — на кроці куба `\/(\d+)`/,
        [ finest_cube, finest_part ] ],
      [ /одноточковий `C` того самого куба при `wall_param` (\d+(?:\.\d+)?) читається \*\*(\d+(?:\.\d+)?) · (\d+(?:\.\d+)?) · (\d+(?:\.\d+)?)\*\* на (\d+) · (\d+) · (\d+) кроках/,
        ->(md) { at = md[1].to_f; named = md.captures.last(3).map(&:to_i); [ at, *named.map { |d| single_c.call(d, at) }, *named ] } ],
      [ /ПОКАЗНИК збігається\*\* — (\d+(?:\.\d+)?) на ґратці \(`\/(\d+)`\) проти (\d+(?:\.\d+)?) на деталі \(`\/(\d+)`\), а по всіх осьових рядках таблиці `n` лежить у смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?)/,
        ->(md) { [ cube_fit.dig(md[2].to_i, :n), md[2].to_i, part_fit.dig(md[4].to_i, :n), md[4].to_i, (all_n.min if md[5] == n_lo_cell), (all_n.max if md[6] == n_hi_cell) ] } ],
      # Each step must be a row's, «втричі з гаком» a ratio in [3, 4), and the coarse row's ratio to the same cube step.
      [ /деталь рахована на кроці (\d+(?:\.\d+)?) мм проти (\d+(?:\.\d+)?) мм у куба, тобто \*\*втричі з гаком грубіше\*\* \(а її рядок «період\/(\d+)» — (\d+(?:\.\d+)?) мм, тобто (\d+(?:\.\d+)?)×\)/,
        lambda do |md|
          # The row whose step the quote names: among those equal at its precision, the NEAREST — at one decimal 0.25
          # prints as «0.2» (half-to-even), so a first match would take a /8 rung for the /10 one the sentence means.
          named_step = ->(fits, q) { fits.values.map { |v| v[:step_mm] }.select { |s| gap_render.call(s, q) == q }.min_by { |s| (s - q.to_f).abs } }
          part_step = named_step.call(part_fit, md[1])
          cube_step = named_step.call(cube_fit, md[2])
          thrice = part_step && cube_step && (3...4).cover?(part_step / cube_step)
          coarse = part_fit.dig(md[3].to_i, :step_mm)
          [ (part_step if thrice), (cube_step if thrice), md[3].to_i, coarse, (coarse / cube_step if coarse && cube_step) ]
        end ],
      [ /переріш деталі з (\d+) на (\d+) поділів \*\*знизив\*\* `C` з (\d+(?:\.\d+)?) до (\d+(?:\.\d+)?)/,
        lambda do |md|
          from, to = part_fit.dig(md[1].to_i, :c), part_fit.dig(md[2].to_i, :c)
          [ md[1].to_i, md[2].to_i, from, (to if from && to && to < from) ]
        end ],
      [ /а куб на тій самій осі повівся немонотонно \((\d+(?:\.\d+)?) → (\d+(?:\.\d+)?) → (\d+(?:\.\d+)?) на (\d+) · (\d+) · (\d+) кроках\)/,
        lambda do |md|
          named = md.captures.last(3).map(&:to_i)
          cs = named.map { |d| cube_fit.dig(d, :c) }
          wobbles = cs.none?(&:nil?) && cs.each_cons(2).map { |x, y| y <=> x }.uniq.size > 1
          [ *cs.map { |v| (v if wobbles) }, *named ]
        end ]
    ]
    checks.each do |re, values|
      m = canon.match(re)
      next failures << "size-gap derivation /#{re.source[0, 60]}…/ is gone or reworded — fix its shape, do not drop it" if m.nil?

      gap_anchors += 1
      values = values.call(m) if values.respond_to?(:call)
      m.captures.zip(values).each do |quoted, value|
        flag(failures, "size-gap derivation «#{m[0][0, 70]}…»", value && gap_render.call(value, quoted), quoted) if value.nil? || gap_render.call(value, quoted) != quoted
      end
    end
    # The two CHAINS: their length is canon's, never this script's — a new rung lengthens the sentence and is held.
    if (m = canon.match(/його `C` на (\S+) кроках ((?:\*\*)?\d+(?:\.\d+)?(?:\*\*)?(?: → (?:\*\*)?\d+(?:\.\d+)?(?:\*\*)?)+) тримає три найдрібніші рядки в смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) завширшки (\d+(?:\.\d+)?) %/))
      gap_anchors += 1
      quoted = chain.call(m[2])
      word = count_word[cube_fit.size]
      failures << "size-gap: the cube chain has #{cube_fit.size} rungs and this guard has no count word for it — extend count_word" if word.nil?
      failures << "size-gap: canon counts the cube chain as «#{m[1]}», the table has #{cube_fit.size} rungs («#{word}»)" if word && apostrophe.call(m[1]) != apostrophe.call(word)
      failures << "size-gap: canon's cube chain has #{quoted.size} values, the table #{cube_fit.size} rungs" if quoted.size != cube_fit.size
      quoted.zip(cube_fit.values).each { |q, v| flag(failures, "size-gap cube chain", gap_render.call(v[:c], q), q) if v && gap_render.call(v[:c], q) != q }
      band_cells = [ shown.dig([ :cube, low_div ], :c), shown.dig([ :cube, finest3.max_by { |d| cube_fit[d][:c] } ], :c) ]
      failures << "size-gap cube band «#{m[3]}–#{m[4]}»: the table shows its extreme rows as «#{band_cells.join('–')}»" unless [ m[3], m[4] ] == band_cells
      flag(failures, "size-gap cube band width «#{m[0][0, 60]}…»", gap_render.call(spread, m[5]), m[5]) if gap_render.call(spread, m[5]) != m[5]
    else
      failures << "size-gap: the cube chain «його `C` на N кроках … тримає три найдрібніші рядки в смузі …» is gone or reworded — fix its shape"
    end
    # ⛔ DECLARED CEILING: «(зварне тіло: 1.155 → 1.046 → 1.025, …)», «+4.3 %» and the ⊕ welded-branch falls are the
    # PRE-HW.33 body's figures — every cache they came from was re-run on the (в) geometry, so they stand as dated
    # record. The live chain is the part's whole axial fit table in step order; its length is canon's, as the cube's —
    # the shape word and the per-step words are derived above (word_checks); here the numbers, and that the last step
    # is smaller than the cube's band.
    if (m = canon.match(/драбинка підігнаного `C` (?:НЕ монотонна|СПАДНА|ЗРОСТАЄ):\*\* після гео-присуду HW\.33 (`\/\d+`(?: → `\/\d+`)*) дають (\d+\.\d+(?: → \d+\.\d+)*) \(прирости ((?:[+−]\d+\.\d+)(?: і [+−]\d+\.\d+)*)\) — (?:спад|підйом) на першому кроці й (?:спад|підйом) на другому, менший за ширину смуги куба/))
      gap_anchors += 1
      named = m[1].scan(/\d+/).map(&:to_i)
      values_q = m[2].split(" → ")
      incs_q = m[3].split(" і ")
      failures << "size-gap: the part chain names #{named}, the table's part axial rows are #{part_fit.keys}" unless named == part_fit.keys
      failures << "size-gap: the part chain quotes #{values_q.size} values and #{incs_q.size} increments for #{part_c.size} rungs" unless values_q.size == part_c.size && incs_q.size == part_c.size - 1
      values_q.zip(part_c).each { |q, v| flag(failures, "size-gap part chain", v && gap_render.call(v, q), q) if v.nil? || gap_render.call(v, q) != q }
      incs_q.zip(incs).each { |q, v| flag(failures, "size-gap part chain increment", v && gap_render.call(v, q), q) if v.nil? || gap_render.call(v, q) != q }
      last_step = part_c.size >= 2 && ((part_c[-1] / part_c[-2]) - 1).abs * 100
      failures << "«… на другому, менший за ширину смуги куба»: the part's last step is #{last_step} % against the cube band's #{spread} %" unless last_step && last_step < spread
    else
      failures << "size-gap: the part's fitted-C chain «драбинка підігнаного `C` …: після гео-присуду HW.33 … дають … (прирости …)» is gone or reworded — fix its shape"
    end
    # The fit COMMAND canon prints: its walls are the cube caches' walls, its cache list is the table's cube rungs —
    # a command that omits --walls overwrites a pinned cache with another sweep (picogk gotcha #14).
    if (m = canon.match(/Команда: `dotnet run -- fea --fit --cells 2 --steps-per-period (\d+) --walls ([-\d.,]+)`[^;]*; кеші `tools\/cad\/cache\/fea\/gibson_ashby_fit\.network\.s\{([\d,]+)\}\.json`/))
      gap_anchors += 1
      walls = m[2].split(",").map(&:to_f)
      cached_walls = cube_fit.values.map { |v| v[:rows].map { |r| r["wall_param"].round(4) } }.uniq
      failures << "size-gap: canon's fit command sweeps #{walls}, the cube caches were measured on #{cached_walls}" unless cached_walls.size == 1 && cached_walls.first == walls.map { |w| w.round(4) }
      failures << "size-gap: canon's fit command runs /#{m[1]}, which is not the canonical pair's cube row" unless cube_fit.key?(m[1].to_i)
      failures << "size-gap: canon lists the cube caches s{#{m[3]}}, the table has #{cube_fit.keys}" unless m[3].split(",").map(&:to_i) == cube_fit.keys
    else
      failures << "size-gap: the cube fit command with its --walls and cache list is gone or reworded — fix its shape"
    end
    # The welded equal-step run as canon describes it: the command's walls are its rows', the step is its step, the element
    # range is its rows' (the retired annulus's «4.2–6.7 млн» stood here as the welded run's until 2026-10-22).
    if (m = canon.match(/Деталь пройдено на кроці КУБА \(`fea cem\/anchor_zone1\.pine\.json --fit --step-div (\d+) --walls ([-\d.,]+)` — (\d+(?:\.\d+)?) мм, (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) млн елементів на точку/))
      gap_anchors += 1
      equal_run = part_fit[m[1].to_i]
      if equal_run.nil?
        failures << "size-gap: canon's equal-step part command runs /#{m[1]}, and the part table has no such row"
      else
        failures << "size-gap: the equal-step part command sweeps #{m[2]}, the /#{m[1]} fit was measured on #{equal_run[:rows].map { |r| r['wall_param'] }}" unless equal_run[:rows].map { |r| r["wall_param"].round(4) } == m[2].split(",").map { |w| w.to_f.round(4) }
        millions = equal_run[:rows].map { |r| r["elements"] / 1e6 }.minmax
        [ [ equal_run[:step_mm], m[3] ], [ millions[0], m[4] ], [ millions[1], m[5] ] ].each do |value, q|
          flag(failures, "size-gap equal-step part run «#{m[0][0, 60]}…»", gap_render.call(value, q), q) if gap_render.call(value, q) != q
        end
      end
    else
      failures << "size-gap: the equal-step part run «Деталь пройдено на кроці КУБА (…)» is gone or reworded — fix its shape"
    end
    # The Richardson caveat under the sweep table: the part's E at the NOMINAL wall, read off its fits — axial at the
    # steps the sentence names, radial on the fit it names — against the sweep rows and the Richardson pair it names.
    nominal_wall = JSON.parse(File.read(File.join(ROOT, "tools/cad/cem/anchor_zone1.pine.json")))["gyroid_wall_param"]
    at_wall = lambda do |d, key|
      pts = part_fit.dig(d, :rows).to_a
      cubic_at.call(pts.map { |r| r["wall_param"] }, pts.map { |r| r[key] }, nominal_wall) if pts.size >= 4 && pts.all? { |r| r[key] }
    end
    swept = ->(div) { sweep["rows"].find { |r| r["step_divisor"] == div } }
    descends = ->(xs) { xs.none?(&:nil?) && xs.each_cons(2).all? { |x, y| y < x } }
    # Named groups: the sentence names eleven steps and four values, and positional numbering is how a capture slips.
    caveat_a = /На новій геометрії розгортка по кроку не монотонна: `\/(?<c6>\d+)` лежить нижче за `\/(?<c8>\d+)` по обох осях \(осьова (?<a6>\d+\.\d+) проти (?<a8>\d+\.\d+), радіальна (?<r6>\d+\.\d+) проти (?<r8>\d+\.\d+)\)/
    caveat_b = /прочитані на номінальній стінці (?<wall>\d+(?:\.\d+)?) кубічною інтерполяцією через чотири найближчі до неї стінки, дають осьове `E` (?<e7>\d+\.\d+) на `\/(?<f7>\d+)` \(між `\/(?<lo7>\d+)` і `\/(?<hi7>\d+)` розгортки\) і (?<e10>\d+\.\d+) на `\/(?<f10>\d+)` \(нижче за `\/(?<u10>\d+)`, (?<e_u10>\d+\.\d+)\), а радіальне на `\/(?<fr>\d+)` — (?<er>\d+\.\d+), нижче і за `\/(?<ra>\d+)`, і за `\/(?<rb>\d+)` \((?<e_rb>\d+\.\d+)\): разом із розгорткою — той самий прилад на (?<na>\S+) кроках осьово й (?<nr>\S+) радіально — по кроку не монотонні ОБИДВІ осі, тож двоточкова екстраполяція з `\/(?<rich_a>\d+)` і `\/(?<rich_b>\d+)` збіжності не доводить ні зверху, ні знизу/
    ma = canon.match(caveat_a)
    mb = canon.match(caveat_b)
    if ma && mb
      gap_anchors += 1
      post = part_fit
      rows_named = %i[c6 c8].map { |k| swept.call(ma[k].to_i) } + %i[lo7 hi7 u10 ra rb rich_a rich_b].map { |k| swept.call(mb[k].to_i) }
      if rows_named.any?(&:nil?) || %i[f7 f10 fr].any? { |k| !post.key?(mb[k].to_i) }
        failures << "size-gap: the Richardson caveat names a sweep step the cache lacks, or a fit that is not a post-HW.33 part row"
      else
        what = "size-gap Richardson caveat"
        r6, r8 = swept.call(ma[:c6].to_i), swept.call(ma[:c8].to_i)
        e7 = at_wall.call(mb[:f7].to_i, "axial_ratio")
        e10 = at_wall.call(mb[:f10].to_i, "axial_ratio")
        er = at_wall.call(mb[:fr].to_i, "radial_ratio")
        u10 = swept.call(mb[:u10].to_i)["axial_ratio"]
        rad_a, rad_b = swept.call(mb[:ra].to_i)["radial_ratio"], swept.call(mb[:rb].to_i)["radial_ratio"]
        [ [ r6["axial_ratio"], ma[:a6] ], [ r8["axial_ratio"], ma[:a8] ], [ r6["radial_ratio"], ma[:r6] ], [ r8["radial_ratio"], ma[:r8] ],
          [ nominal_wall, mb[:wall] ], [ e7, mb[:e7] ], [ e10, mb[:e10] ], [ u10, mb[:e_u10] ], [ er, mb[:er] ], [ rad_b, mb[:e_rb] ] ].each do |value, q|
          flag(failures, what, value && gap_render.call(value, q), q) if value.nil? || gap_render.call(value, q) != q
        end
        failures << "«/#{ma[:c6]} лежить нижче за /#{ma[:c8]} по обох осях»: the sweep says otherwise" unless r6["axial_ratio"] < r8["axial_ratio"] && r6["radial_ratio"] < r8["radial_ratio"]
        band7 = [ swept.call(mb[:lo7].to_i)["axial_ratio"], swept.call(mb[:hi7].to_i)["axial_ratio"] ].minmax
        failures << "«/#{mb[:f7]} між /#{mb[:lo7]} і /#{mb[:hi7]} розгортки»: it reads #{e7}, the sweep #{band7}" unless e7 && e7 > band7[0] && e7 < band7[1]
        failures << "«/#{mb[:f10]} нижче за /#{mb[:u10]}»: it reads #{e10}, the sweep #{u10}" unless e10 && e10 < u10
        failures << "«радіальне на /#{mb[:fr]} нижче і за /#{mb[:ra]}, і за /#{mb[:rb]}»: it reads #{er}, the sweep #{[ rad_a, rad_b ]}" unless er && er < rad_a && er < rad_b
        merged_ax = (post.map { |d, v| [ v[:step_mm], at_wall.call(d, "axial_ratio") ] } + sweep["rows"].map { |r| [ r["step_mm"], r["axial_ratio"] ] }).reject { |_, e| e.nil? }.sort_by { |st, _| -st }.map(&:last)
        merged_rad = (post.map { |d, v| [ v[:step_mm], at_wall.call(d, "radial_ratio") ] } + sweep["rows"].map { |r| [ r["step_mm"], r["radial_ratio"] ] }).reject { |_, e| e.nil? }.sort_by { |st, _| -st }.map(&:last)
        { "осьово" => [ merged_ax, mb[:na] ], "радіально" => [ merged_rad, mb[:nr] ] }.each do |axis_word, (ladder_e, count_q)|
          failures << "«по кроку не монотонні ОБИДВІ осі»: merged by step the #{axis_word} ladder IS monotone — #{ladder_e}" if descends.call(ladder_e) || descends.call(ladder_e.reverse)
          word = count_word[ladder_e.size]
          failures << "«на #{count_q} кроках #{axis_word}»: the ladder has #{ladder_e.size} steps («#{word}»)" unless word && apostrophe.call(count_q) == apostrophe.call(word)
        end
      end
    else
      failures << "size-gap: the Richardson caveat under the sweep table (the non-monotone sweep, then the fits read at the nominal wall) is gone or reworded — fix its shape"
    end
    # The «доказ зверху» after the re-run: the /32 fit read at the nominal wall against the two sweep rows the sentence
    # names — the same cubic interpolation as the caveat, held with the same ceiling (a reading, not a measurement).
    if (m = canon.match(/фіт `\/(\d+)`, перепрогнаний 2026-10-23 і прочитаний на тій самій номінальній стінці, дає (\d+\.\d+) — вище за `\/(\d+)` розгортки \((\d+\.\d+)\) і нижче за `\/(\d+)` \((\d+\.\d+)\), тобто (\S+) крок осьової драбини/))
      gap_anchors += 1
      e_fit = part_fit.key?(m[1].to_i) ? at_wall.call(m[1].to_i, "axial_ratio") : nil
      lo, hi = swept.call(m[3].to_i), swept.call(m[5].to_i)
      if e_fit.nil? || lo.nil? || hi.nil?
        failures << "size-gap: the «доказ зверху» sentence names a fit or a sweep step the caches lack"
      else
        [ [ e_fit, m[2] ], [ lo["axial_ratio"], m[4] ], [ hi["axial_ratio"], m[6] ] ].each { |value, q| flag(failures, "size-gap «доказ зверху»", gap_render.call(value, q), q) if gap_render.call(value, q) != q }
            failures << "«фіт /#{m[1]} … вище за /#{m[3]} і нижче за /#{m[5]}»: it reads #{e_fit}, the sweep #{[ lo['axial_ratio'], hi['axial_ratio'] ]}" unless e_fit > lo["axial_ratio"] && e_fit < hi["axial_ratio"]
        # «Зверху» is a claim about the STEP too: the fit must be finer than both rows it is set between.
        failures << "«доказ зверху»: the /#{m[1]} fit (#{part_fit.dig(m[1].to_i, :step_mm)} mm) is not finer than both /#{m[3]} and /#{m[5]}" unless part_fit.dig(m[1].to_i, :step_mm) < [ lo["step_mm"], hi["step_mm"] ].min
        ordinal = { 5 => "пʼятий", 6 => "шостий", 7 => "сьомий", 8 => "восьмий", 9 => "девʼятий", 10 => "десятий" }
        steps_desc = (post.map { |_, v| v[:step_mm] } + sweep["rows"].map { |r| r["step_mm"] }).uniq.sort.reverse
        position = steps_desc.index(part_fit.dig(m[1].to_i, :step_mm))
        failures << "«#{m[7]} крок осьової драбини»: the /#{m[1]} fit is step #{position && position + 1} of #{steps_desc.size} from the coarsest («#{position && ordinal[position + 1]}»)" unless position && apostrophe.call(m[7]) == apostrophe.call(ordinal[position + 1])
      end
    else
      failures << "size-gap: the «доказ зверху» sentence (the re-run /32 fit at the nominal wall against the sweep) is gone or reworded — fix its shape"
    end
    # «наступний рядок деталі (`/64`) коштує ~16× … росте як N⁴»: the power is the sweep's own — elements × axial CG
    # iterations between its two finest rows — and the factor is that power of the step ratio to the finest part row.
    if (m = canon.match(/наступний рядок деталі \(`\/(\d+)`\) коштує ~(\d+)× цього прогону \(ціна прогону росте як N([⁰¹²³⁴⁵⁶⁷⁸⁹]) — так її міряє розгортка: елементи × ітерації CG\)/))
      gap_anchors += 1
      fine2 = sweep["rows"].sort_by { |r| r["step_mm"] }.first(2)
      run_cost = ->(r) { r["elements"].to_f * r["axial_iterations"] }
      power = Math.log(run_cost.call(fine2[0]) / run_cost.call(fine2[1])) / Math.log(fine2[1]["step_mm"] / fine2[0]["step_mm"])
      quoted_power = "⁰¹²³⁴⁵⁶⁷⁸⁹".index(m[3])
      failures << "«росте як N#{m[3]}»: the sweep's two finest rows give a cost power of #{power.round(2)}" unless power.round == quoted_power
      factor = (m[1].to_f / finest_part)**quoted_power
      failures << "«наступний рядок деталі (/#{m[1]}) коштує ~#{m[2]}×»: from the finest part row /#{finest_part} that is ~#{factor.round(1)}×" unless factor.round == m[2].to_i && m[1].to_i > finest_part
    else
      failures << "size-gap: «наступний рядок деталі (/N) коштує ~K× … росте як Nᵖ» is gone or reworded — fix its shape"
    end
    # EVERY fit command canon prints carries the walls of the cache it writes: a bare one overwrites a pinned cache with
    # another sweep (picogk gotcha #14), and prose like «ті самі вісім стінок» holds nothing.
    fit_commands = canon.scan(/`((?:dotnet run -- )?fea (?:cem\/anchor_zone1\.pine\.json )?--fit [^`]*)`/).flatten
    failures << "size-gap: canon prints #{fit_commands.size} fit commands, at least 4 expected — a rewording has DISARMED this check" if fit_commands.size < 4
    fit_commands.each do |cmd|
      cmd_walls = cmd[/--walls ([-\d.,]+)/, 1]&.split(",")&.map { |w| w.to_f.round(4) }
      cmd_fit = cmd.include?("cem/") ? part_fit[cmd[/--step-div (\d+)/, 1].to_i] : cube_fit[cmd[/--steps-per-period (\d+)/, 1].to_i]
      cmd_cached = cmd_fit && cmd_fit[:rows].map { |r| r["wall_param"].round(4) }
      failures << "size-gap: canon's `#{cmd}` #{cmd_walls ? "sweeps #{cmd_walls}" : 'has no --walls'}, and its cache #{cmd_cached ? "was measured on #{cmd_cached}" : 'is not in the table'}" unless cmd_walls && cmd_walls == cmd_cached
      failures << "size-gap: canon's `#{cmd}` runs the radial case, and that fit carries no radial C" if cmd.include?("--with-radial") && cmd_fit && cmd_fit[:rc].nil?
    end
  end
end

# ── 9. THE STEP LADDER (§5.2, HW.23 — the re-sweep of 2026-10-23) ──────────────────────────────────────────────────
#
# The table under the sweep's caveat lists every step of the merged ladder with its lock flag; the sentences under it
# derive the unlocked chain's convergence, the locked rows' cost against the converged (finest unlocked) row, the
# retired Richardson's error and the two readings `105` takes. Held: every cell, every derived figure at its quoted
# precision, every direction word, the row count (a step added or dropped without the table following reds), and the
# identity control's presence. ⛔ DECLARED CEILING: it does not re-run the FE and cannot tell a lock from any other
# coherent error — «замикання» is the reading canon gives the saw, held by the convergence of the unlocked steps.
ladder_rows_seen = 0
ladder_steps_matched = []
canon.scan(/^\| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}(період\/\d+|11\/\d+)\*{0,2} \| \*{0,2}(замкнений|незамкнений)\*{0,2} \| \*{0,2}([0-9.]+) %\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \| \*{0,2}([0-9.]+)\*{0,2} \|$/) do
  step_q, label_q, lock_q, por_q, ax_q, rad_q = Regexp.last_match.captures
  row = step_ladder.min_by { |r| (r["step_mm"] - step_q.to_f).abs }
  next failures << "step-ladder row #{step_q} mm: no cached step within rounding" if row.nil? || (row["step_mm"] - step_q.to_f).abs > 5e-5

  ladder_rows_seen += 1
  ladder_steps_matched << row["step_mm"]
  want_label = row["locked"] ? "період/#{(RIM_PERIOD_MM / row['step_mm']).round}" : "11/#{(11.0 / row['step_mm']).round}"
  failures << "step-ladder row #{step_q} mm: canon labels it #{label_q}, the cache's step is #{want_label}" if label_q != want_label
  failures << "step-ladder row #{step_q} mm: canon says #{lock_q}, the step #{row['locked'] ? 'divides' : 'does not divide'} the axial period" if lock_q != (row["locked"] ? "замкнений" : "незамкнений")
  { "porosity %" => [ row["porosity"] * 100, por_q ], "axial" => [ row["axial_ratio"], ax_q ], "radial" => [ row["radial_ratio"], rad_q ] }.each do |cell, (v, q)|
    rendered = format("%.#{q.include?('.') ? q.split('.').last.length : 0}f", v)
    flag(failures, "step-ladder #{step_q} mm #{cell}", rendered, q) if rendered != q
  end
end
failures << "the step-ladder table has #{ladder_rows_seen} rows against #{step_ladder.size} cached steps — a step was added or dropped and the table did not follow" if ladder_rows_seen != step_ladder.size
failures << "the step-ladder table matches #{ladder_steps_matched.uniq.size} DISTINCT cached steps of #{step_ladder.size} — a row stands on another row's step" if ladder_steps_matched.uniq.size != step_ladder.size
ladder_anchors = 0
r4 = ->(v) { format("%.4f", v) }
at_q = ->(v, q) { format("%.#{q.include?('.') ? q.split('.').last.length : 0}f", v) }
if (m = canon.match(/осьова ([0-9.]+) → ([0-9.]+) → ([0-9.]+), радіальна ([0-9.]+) → ([0-9.]+) → ([0-9.]+) \(останній крок ([−+]?[0-9.]+) % і ([−+]?[0-9.]+) %[;)]/))
  ladder_anchors += 1
  failures << "the unlocked-chain sentence names three steps, the ladder has #{unlocked_rows.size}" unless unlocked_rows.size == 3
  if unlocked_rows.size == 3
    (unlocked_rows.map { |r| r["axial_ratio"] } + unlocked_rows.map { |r| r["radial_ratio"] }).zip(m.captures.first(6)).each { |v, q| flag(failures, "unlocked chain", r4.call(v), q) if r4.call(v) != q }
    last = %w[axial_ratio radial_ratio].map { |k| ((unlocked_rows[2][k] / unlocked_rows[1][k]) - 1) * 100 }
    last.zip(m.captures.last(2)).each { |v, q| flag(failures, "unlocked chain last step", gap_render.call(v, q), q) if gap_render.call(v, q) != q }
  end
else
  failures << "the unlocked-chain sentence «осьова A → B → C, радіальна … (останній крок X % і Y %)» is gone or reworded — fix its shape"
end
cost = ->(div, key) { r = locked_rows.find { |x| (RIM_PERIOD_MM / x["step_mm"]).round == div }; r && ((r[key] / finest_unlocked[key]) - 1) * 100 }
if (m = canon.match(/`\/(\d+)` і `\/(\d+)` лежать на ([0-9.]+) і ([0-9.]+) % НИЖЧЕ збіжного осьово \(([0-9.]+) і ([0-9.]+) % радіально\), `\/(\d+)` — на ([0-9.]+) % вище, і лише `\/(\d+)` сходить із замиканням осьово \(\+([0-9.]+) %\), радіально ж лишається на ([0-9.]+) % нижче/))
  ladder_anchors += 1
  a, b, c, d = m[1].to_i, m[2].to_i, m[7].to_i, m[9].to_i
  vals = { "/#{a} axial under" => [ cost.call(a, "axial_ratio"), m[3], :neg ], "/#{b} axial under" => [ cost.call(b, "axial_ratio"), m[4], :neg ],
           "/#{a} radial under" => [ cost.call(a, "radial_ratio"), m[5], :neg ], "/#{b} radial under" => [ cost.call(b, "radial_ratio"), m[6], :neg ],
           "/#{c} axial over" => [ cost.call(c, "axial_ratio"), m[8], :pos ], "/#{d} axial over" => [ cost.call(d, "axial_ratio"), m[10], :pos ],
           "/#{d} radial under" => [ cost.call(d, "radial_ratio"), m[11], :neg ] }
  vals.each do |label, (v, q, sign)|
    next failures << "lock cost #{label}: the ladder has no such locked step" if v.nil?

    failures << "lock cost #{label}: canon gives it the sign of «#{sign == :neg ? 'нижче' : 'вище'}», the cache gives #{v}" unless sign == :neg ? v.negative? : v.positive?
    flag(failures, "lock cost #{label}", at_q.call(v.abs, q), q) if at_q.call(v.abs, q) != q
  end
  failures << "lock cost: canon names /#{d} as the finest locked step, the ladder's is /#{(RIM_PERIOD_MM / finest_locked['step_mm']).round}" unless d == (RIM_PERIOD_MM / finest_locked["step_mm"]).round
else
  failures << "the lock-cost sentence «`/16` і `/20` лежать на … НИЖЧЕ збіжного осьово (…), `/24` — на … вище, і лише `/32` …» is gone or reworded — fix its shape"
end
pair2 = sweep["rows"].sort_by { |r| r["step_mm"] }.first(2)
richardson = ->(key, order) { pair2[0][key] + ((pair2[0][key] - pair2[1][key]) / (((pair2[1]["step_mm"] / pair2[0]["step_mm"])**order) - 1.0)) }
if (m = canon.match(/двоточковий Річардсон із замкненої пари `\/(\d+)`→`\/(\d+)` \(([0-9.]+)–([0-9.]+) осьово, ([0-9.]+)–([0-9.]+) радіально, рядок знято\) екстраполював похибку замикання — на (\d+)–(\d+) % нижче збіжного осьово, на (\d+)–(\d+) % радіально/))
  ladder_anchors += 1
  failures << "retired Richardson: canon names /#{m[1]}→/#{m[2]}, the sweep's two finest rows are /#{pair2[1]['step_divisor']}→/#{pair2[0]['step_divisor']}" unless m[1].to_i == pair2[1]["step_divisor"] && m[2].to_i == pair2[0]["step_divisor"]
  ax = [ richardson.call("axial_ratio", 1), richardson.call("axial_ratio", 2) ].minmax
  rd = [ richardson.call("radial_ratio", 1), richardson.call("radial_ratio", 2) ].minmax
  [ *ax, *rd ].zip(m.captures[2, 4]).each { |v, q| flag(failures, "retired Richardson band", format("%.3f", v), q) if format("%.3f", v) != q }
  under_ax = ax.map { |v| (1 - (v / finest_unlocked["axial_ratio"])) * 100 }.minmax
  under_rd = rd.map { |v| (1 - (v / finest_unlocked["radial_ratio"])) * 100 }.minmax
  [ *under_ax, *under_rd ].zip(m.captures[6, 4]).each { |v, q| flag(failures, "retired Richardson under the converged reading", format("%.0f", v), q) if format("%.0f", v) != q }
else
  failures << "the retired-Richardson sentence «двоточковий Річардсон із замкненої пари … екстраполював похибку замикання — на …» is gone or reworded — fix its shape"
end
if (m = canon.match(/Збіжне прочитання деталі — найдрібніший незамкнений крок: осьова ([0-9.]+), радіальна ([0-9.]+)\*\*; найдрібніший замкнений \(`\/(\d+)`\) — другий кінець дужки, і `105` бере по осі несприятливий для твердження \(нижчий\) із двох — це \*\*прочитання `105`\*\*, не збіжне: осьову ([0-9.]+) \((незамкнений|замкнений)\), радіальну ([0-9.]+) \((незамкнений|замкнений)\); кожен сирий рядок драбини має нижчим радіальне, збіжне прочитання теж \(осьова вища за радіальну на ([0-9.]+) %\), і прочитання `105` — осьове вище за радіальне на ([0-9.]+) %/))
  ladder_anchors += 1
  flag(failures, "converged reading axial", r4.call(finest_unlocked["axial_ratio"]), m[1]) if r4.call(finest_unlocked["axial_ratio"]) != m[1]
  flag(failures, "converged reading radial", r4.call(finest_unlocked["radial_ratio"]), m[2]) if r4.call(finest_unlocked["radial_ratio"]) != m[2]
  failures << "the converged-reading sentence names /#{m[3]} as the finest locked step, the ladder's is /#{(RIM_PERIOD_MM / finest_locked['step_mm']).round}" unless m[3].to_i == (RIM_PERIOD_MM / finest_locked["step_mm"]).round
  { "axial" => [ m[4], m[5] ], "radial" => [ m[6], m[7] ] }.each do |ax, (q, which_q)|
    which = finest_unlocked["#{ax}_ratio"] <= finest_locked["#{ax}_ratio"] ? "незамкнений" : "замкнений"
    flag(failures, "105's #{ax} reading (the adverse end)", r4.call(part_reading[ax]), q) if r4.call(part_reading[ax]) != q
    flag(failures, "105's #{ax} reading — which end", which, which_q) if which != which_q
  end
  failures << "«кожен сирий рядок драбини має нижчим радіальне»: a ladder row has the axial reading lower" unless step_ladder.all? { |r| r["radial_ratio"] < r["axial_ratio"] }
  failures << "«осьове вище за радіальне»: 105's radial reading is not below its axial one" unless part_reading["radial"] < part_reading["axial"]
  gap_conv = ((finest_unlocked["axial_ratio"] / finest_unlocked["radial_ratio"]) - 1) * 100
  flag(failures, "the converged pair's gap", at_q.call(gap_conv, m[8]), m[8]) if at_q.call(gap_conv, m[8]) != m[8]
  gap_rd = ((part_reading["axial"] / part_reading["radial"]) - 1) * 100
  flag(failures, "105's readings' gap", at_q.call(gap_rd, m[9]), m[9]) if at_q.call(gap_rd, m[9]) != m[9]
  # every copy of 105's gap in canon (the banner carries one too), not the first — two homes, one number
  gap_copies = canon.scan(/прочитання `105` — осьове вище за радіальне на ([0-9.]+) %/).flatten
  failures << "105's gap «осьове вище за радіальне на …» is quoted #{gap_copies.size}× in canon — expected at least twice (the banner and the ladder paragraph)" if gap_copies.size < 2
  gap_copies.each { |q| flag(failures, "105's readings' gap (a copy)", at_q.call(gap_rd, q), q) if at_q.call(gap_rd, q) != q }
else
  failures << "the converged-reading sentence «Збіжне прочитання деталі — найдрібніший незамкнений крок: …» is gone or reworded — fix its shape"
end
if canon.include?("Контроль ідентичності: рядок `/8`, прогнаний перевиміром через `--step-mm`, відтворює запінений `/8` побітово.")
  ladder_anchors += 1
  failures << "the identity-control sentence stands, but the re-sweep's /8 row (anchor_zone1_pine.h250um.json) is not in cache/fea" unless fine_files.any? { |f| f.end_with?("anchor_zone1_pine.h250um.json") }
else
  failures << "the identity-control sentence of the step ladder is gone or reworded — fix its shape"
end
# The headline stiffness — every «≈X (ГПа) осьово» / «≈Y (ГПа) радіально» in canon and in 02_06 is the converged (finest
# unlocked) row × E_solid 110 GPa at one decimal; «до присуду ≈10.9 · ≈7.7» carries no axis word and is not scanned.
gpa = { "осьово" => finest_unlocked["axial_ratio"] * 110, "радіально" => finest_unlocked["radial_ratio"] * 110 }
[ [ "01_01", canon ], [ "02_06", File.read(File.join(ROOT, "docs/02_06_Unit_Economics_and_BOM.md")) ] ].each do |name, doc|
  gpa.each do |axis, v|
    hits = doc.scan(/≈(\d+\.\d)(?: ГПа)?\*{0,2} #{axis}/).flatten
    failures << "#{name}: no «≈X #{axis}» headline stiffness found — the sentence shape moved" if hits.empty?
    hits.each { |q| flag(failures, "#{name} headline stiffness #{axis}", format("%.1f", v), q) if format("%.1f", v) != q }
  end
end
if (m = canon.match(/збіжна радіальна — ([0-9.]+) осьової/))
  ladder_anchors += 1
  flag(failures, "«збіжна радіальна — X осьової»", format("%.2f", finest_unlocked["radial_ratio"] / finest_unlocked["axial_ratio"]), m[1]) if format("%.2f", finest_unlocked["radial_ratio"] / finest_unlocked["axial_ratio"]) != m[1]
else
  failures << "«збіжна радіальна — X осьової» is gone or reworded — fix its shape"
end
if (m = canon.match(/Збіжне прочитання перевиміру HW\.23 \(незамкнений крок 11\/(\d+)\)/))
  ladder_anchors += 1
  failures << "limit (3) names the converged step 11/#{m[1]}; the finest unlocked step is 11/#{(11.0 / finest_unlocked['step_mm']).round}" if m[1].to_i != (11.0 / finest_unlocked["step_mm"]).round
else
  failures << "limit (3) «Збіжне прочитання перевиміру HW.23 (незамкнений крок 11/N)» is gone or reworded — fix its shape"
end
EXPECTED_LADDER_ANCHORS = 7
failures << "only #{ladder_anchors} of #{EXPECTED_LADDER_ANCHORS} step-ladder derivation anchors matched — a canon rewording has DISARMED a comparison; fix the sentence shape, do not lower this number" if ladder_anchors < EXPECTED_LADDER_ANCHORS

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

EXPECTED_ANCHORS = 13
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
  # The part's two READINGS per axis since HW.23 (2026-10-23): the finest unlocked row (converged) and the finest locked
  # one — no extrapolation; `105` takes per axis the lower of the two.
  reading_of = ->(row, key) { row[key] }
  body = lambda do |radial, axial|
    bulk = radial / ((1 + nu) * (1 - (2 * nu)))
    dev = ((3 * bulk) - Math.sqrt((9 * bulk * bulk) - (8 * bulk * axial))) / 2
    { axial:, bulk:, dev:, nu: (bulk - dev) / 2 / bulk }
  end
  # The part readings `105` takes (per axis the adverse end of the finest-step bracket) are held to 105's OWN cache.
  if File.exist?(CACHE_105)
    r105 = JSON.parse(File.read(CACHE_105)).dig("inputs", "fe_readings") || {}
    { "radial_reading" => part_reading["radial"], "axial_reading" => part_reading["axial"] }.each do |key, mine|
      failures << "105's cached #{key} #{r105[key].inspect} is not this layer's finest-step reading #{mine} — the rule moved" unless r105[key] && (r105[key] - mine).abs < 1e-12
    end
  else
    failures << "105's cache is not committed — the part readings `105` takes have nothing to be held to"
  end
  equal16 = rung.call(16)
  # density-matched to the CONVERGED part row (the finest unlocked), not to the locked /16 of the pinned sweep
  matched = per["rows"].select { |r| (r["porosity"] - finest_unlocked["porosity"]).abs < 0.005 }.sort_by { |r| r["steps_per_period"] }
  if matched.empty?
    failures << "no periodic rung sits within half a point of the part's porosity — canon's density-matched pairs have no rung"
  else
    # The rung RANGE canon quotes is read from canon and held to the density-matched set; no rung list lives here.
    lo_s = matched.first["steps_per_period"]
    hi_s = matched.last["steps_per_period"]
    inside = per["rows"].map { |r| r["steps_per_period"] }.select { |st| st.between?(lo_s, hi_s) }.sort
    failures << "the density-matched rungs #{matched.map { |r| r['steps_per_period'] }} are not one run of the ladder (#{inside}) — canon quotes them as a range" unless inside == matched.map { |r| r["steps_per_period"] }
    failures << "canon refuses /16 for its density; /16 is #{equal16['porosity']} against the part's #{finest_unlocked['porosity']}" if (equal16["porosity"] - finest_unlocked["porosity"]).abs < 0.005
    bases = [ body.call(reading_of.call(finest_unlocked, "radial_ratio"), reading_of.call(finest_unlocked, "axial_ratio")),
              body.call(reading_of.call(finest_locked, "radial_ratio"), reading_of.call(finest_locked, "axial_ratio")) ]
    pairs = bases.product(matched)
    dil_low = pairs.map { |pt, r| (1 - (pt[:bulk] / (r["C11"] + r["C12"]))) * 100 }
    dev_gap = pairs.map { |pt, r| ((pt[:dev] / (r["C11"] - r["C12"])) - 1) * 100 }
    axial_gap = pairs.map { |pt, r| ((pt[:axial] / r["E100"]) - 1) * 100 }
    # the lock cost of the sweep's /16 against the converged reading — what the retired extrapolation used to misread
    lock16 = (1 - (two[0]["axial_ratio"] / finest_unlocked["axial_ratio"])) * 100
    # A raw part row against each density-matched rung, carried to that rung's density by the canonical pair's n (layer 7).
    raw_gaps = ->(r) { matched.map { |g| (((r["axial_ratio"] * (((1 - g["porosity"]) / (1 - r["porosity"]))**n_pair)) / g["E100"]) - 1) * 100 } }
    failures << "the canonical pair's cache is missing — the density-matched raw-row comparison has no n" if n_pair.nil?
    mu_s = 1.0 / (2 * (1 + nu))
    field = ->(r, theta) { r["fields"].find { |x| (x["theta_deg"] - theta).abs < 1e-9 } || {} }
    pq = ->(r, theta, q) { field.call(r, theta).dig("principal_over_sigma_w", q) }
    band = ->(theta, q) { matched.map { |r| pq.call(r, theta, q) }.minmax }
    spread = ->(v) { (v.max / v.min) - 1 }
    plateau_rows = ladder["rows"].select { |r| r["cells_per_side"] >= 6 }
    plateau = plateau_rows.map { |r| r["axial_ratio"] }
    kp_fall = ->(r) { (1 - ((pq.call(r, 45.0, "p99") * Math.sqrt(field.call(r, 45.0)["modulus_ratio"])) / (pq.call(r, 0.0, "p99") * Math.sqrt(field.call(r, 0.0)["modulus_ratio"])))) * 100 }
    re_dil = /рівновісний розтяг у площині `C11 \+ C12` на всіх парах «база × рунг» рівної густини (?:вищий|нижчий) за матеріальний на (\d+)–(\d+) % \(до присуду HW\.33 — нижчий на \d+–\d+ %, звідки тоді й `ν\*` \d+(?:\.\d+)?\), а `ν\*` тіла тепер (\d+(?:\.\d+)?) проти (\d+(?:\.\d+)?)\./
    # every direction word is a CAPTURE derived from the pairs (guard-craft #186): one sign over all pairs, or the sentence
    # is wrong — the dilatational term, the deviatoric term, the conclusion's two words and the Hue clause's two
    want_dil = dil_low.all?(&:negative?) ? "вищий" : dil_low.all?(&:positive?) ? "нижчий" : nil
    want_dev = dev_gap.all?(&:positive?) ? "вищий" : dev_gap.all?(&:negative?) ? "нижчий" : nil
    failures << "the in-plane dilatational term has no one sign over the density-matched pairs: #{dil_low}" if want_dil.nil?
    failures << "the deviatoric term has no one sign over the density-matched pairs: #{dev_gap}" if want_dev.nil?
    if (dm = canon.match(/рівної густини (вищий|нижчий) за матеріальний на \d+–\d+ % \(до присуду HW\.33/))
      flag(failures, "periodic (3) «вищий/нижчий» for C11 + C12", want_dil, dm[1]) if want_dil && dm[1] != want_dil
    end
    if (dm = canon.match(/Девіаторний член `C11 − C12` — (вищий|нижчий) за матеріальний на всіх/))
      flag(failures, "periodic (3) «вищий/нижчий» for C11 − C12", want_dev, dm[1]) if want_dev && dm[1] != want_dev
    else
      failures << "periodic (3) «Девіаторний член `C11 − C12` — вищий/нижчий за матеріальний на всіх …» is gone or reworded — fix its shape"
    end
    softer = ->(want) { want == "нижчий" ? "мʼякше" : "жорсткіше" }
    if (dm = canon.match(/тож тіло `106` (мʼякше|жорсткіше) за матеріал на зсув у площині й (мʼякше|жорсткіше) на рівновісний розтяг/))
      flag(failures, "periodic (3) conclusion — shear", softer.call(want_dev), dm[1]) if want_dev && dm[1] != softer.call(want_dev)
      flag(failures, "periodic (3) conclusion — dilatation", softer.call(want_dil), dm[2]) if want_dil && dm[2] != softer.call(want_dil)
    else
      failures << "periodic (3) conclusion «тож тіло `106` … за матеріал на зсув у площині й … на рівновісний розтяг» is gone or reworded — fix its shape"
    end
    if (dm = canon.match(/ні (вищий|нижчий) рівновісний, ні (вищий|нижчий) девіаторний член йому не суперечить/))
      flag(failures, "periodic (3) Hue clause — dilatational", want_dil, dm[1]) if want_dil && dm[1] != want_dil
      flag(failures, "periodic (3) Hue clause — deviatoric", want_dev, dm[2]) if want_dev && dm[2] != want_dev
    else
      failures << "periodic (3) Hue clause «ні … рівновісний, ні … девіаторний член йому не суперечить» is gone or reworded — fix its shape"
    end
    # ⛔ 00_07 HW.23's Стан points to these two homes and carries no copy of this comparison — do not re-add one there:
    # this guard does not read the tracker, so a copy would stand unguarded.
    # SUMMARY §106 carries the same comparison in English — direction words derived, ranges held (two homes, one measurement)
    summary = File.read(File.join(ROOT, "docs/protocols/ebfc/in_silico/SUMMARY.md"))
    en = ->(want) { want == "вищий" ? "higher" : "lower" }
    if (sm = summary.match(/its in-plane\s+dilatational term C11 \+ C12 is (higher|lower) on every density-matched pairing of basis and rung \(by (\d+)–(\d+) %\) and its deviatoric term\s+C11 − C12 (higher|lower) \(by (\d+)–(\d+) %\)/))
      flag(failures, "SUMMARY §106 C11 + C12 direction", en.call(want_dil), sm[1]) if want_dil && sm[1] != en.call(want_dil)
      flag(failures, "SUMMARY §106 C11 − C12 direction", en.call(want_dev), sm[4]) if want_dev && sm[4] != en.call(want_dev)
      [ [ sm[2], dil_low.map(&:abs).min ], [ sm[3], dil_low.map(&:abs).max ], [ sm[5], dev_gap.map(&:abs).min ], [ sm[6], dev_gap.map(&:abs).max ] ].each do |q, v|
        flag(failures, "SUMMARY §106 lattice-vs-material range", format("%.0f", v), q) if format("%.0f", v) != q
      end
    else
      failures << "SUMMARY §106 «its in-plane dilatational term C11 + C12 is higher/lower on every density-matched pairing … (by X–Y %) and its deviatoric term C11 − C12 … (by X–Y %)» is gone or reworded — fix its shape"
    end
    checks = [
      [ /порозність (\d+(?:\.\d+)?) % проти (\d+(?:\.\d+)?) % у деталі pine на період\/16/,
        [ finest["porosity"] * 100, two[0]["porosity"] * 100 ] ],
      [ /\*\*C44 — (\d+(?:\.\d+)?) стелі Фойгта/, [ finest["C44"] / (finest["solid_fraction_meshed"] * mu_s) ] ],
      [ /`A` ≈ (\d+(?:\.\d+)?), тобто/, [ finest["zener"] ] ],
      [ /`E\[110\]` ≈ (\d+(?:\.\d+)?)·`E\[100\]`/, [ finest["E110"] / finest["E100"] ] ],
      [ /її `E\[100\]` \((\d+(?:\.\d+)?)\) лежить усередині драбини з плитами без тертя на тому самому кроці \((\d+(?:\.\d+)?)–(\d+(?:\.\d+)?)\), на (\d+(?:\.\d+)?) % нижче її плато (\d+)–(\d+) комірок/,
        [ equal16["E100"], ladder["rows"].map { |r| r["axial_ratio"] }.min, ladder["rows"].map { |r| r["axial_ratio"] }.max,
          (1 - (equal16["E100"] / (plateau.sum / plateau.size))) * 100, *plateau_rows.map { |r| r["cells_per_side"] }.minmax ] ],
      [ /Осьове читання ДЕТАЛІ відносно `E\[100\]` ґратки — на всіх парах «база × рунг» рівної густини \(незамкнене й замкнене найдрібніші прочитання деталі проти рунгів період\/(\d+)–\/(\d+)\) — від (−\d+(?:\.\d+)?) % до ([−+]\d+(?:\.\d+)?) %: деталь нижча на (\d+) парах із (\d+), але знака розриву драбина не встановлює\. Рівний крок базою не є: сира деталь на період\/16 замкнена й лежить на (\d+(?:\.\d+)?) % нижче збіжного прочитання, а фазово-замкнений куб там на іншій густині \((\d+(?:\.\d+)?) % проти (\d+(?:\.\d+)?) % у деталі на тому ж кроці\)/,
        [ lo_s, hi_s, axial_gap.min, axial_gap.max, axial_gap.count(&:negative?), pairs.size, lock16,
          equal16["porosity"] * 100, two[0]["porosity"] * 100 ] ],
      [ re_dil, [ dil_low.map(&:abs).min, dil_low.map(&:abs).max, bases[0][:nu], finest["nu_star"] ] ],
      [ /Девіаторний член `C11 − C12` — (?:вищий|нижчий) за матеріальний на всіх (\d+) парах \(від ([−+]\d+(?:\.\d+)?) % до ([−+]\d+(?:\.\d+)?) %/,
        [ dev_gap.count(&:negative?), dev_gap.min, dev_gap.max ] ],
      [ /а сирий рядок деталі на період\/(\d+) \((\d+(?:\.\d+)?)\), зведений канонним `n` (\d+(?:\.\d+)?) до густини кожного з рунгів рівної густини, лягає проти них від ([−+]\d+(?:\.\d+)?) % до ([−+]\d+(?:\.\d+)?) % — з обома знаками/,
        lambda do |md|
          row = sweep["rows"].find { |r| r["step_divisor"] == md[1].to_i }
          gaps = row && n_pair && raw_gaps.call(row)
          mixed = gaps && gaps.min.negative? && gaps.max.positive?
          [ md[1].to_i, row && row["axial_ratio"], n_pair, (gaps.min if mixed), (gaps.max if mixed) ]
        end ],
      [ /На рунгах рівної густини \(період\/(\d+)–\/(\d+)\) p99 лежить у смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) на θ = 0 і (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?) на θ = 45°, p99\.9 на θ = 0 — у смузі (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?), а максимум не збігається \(на θ = 0 — (\d+(?:\.\d+)?)–(\d+(?:\.\d+)?)\), тож прочитанням він не є/,
        [ lo_s, hi_s, *band.call(0.0, "p99"), *band.call(45.0, "p99"), *band.call(0.0, "p99.9"), *band.call(0.0, "max") ] ],
      [ /на кожному рунгу драбини він на 45° нижчий, ніж на 0°, а `√E` — вищий, тож добуток `k_p·√E` за p99 від 0° до 45° падає \(на рунгах рівної густини — на (\d+)–(\d+) %\)/,
        matched.map(&kp_fall).minmax ]
    ]
    checks.each do |re, values|
      m = canon.match(re)
      values = values.call(m) if m && values.respond_to?(:call)
      next failures << "periodic derivation /#{re.source[0, 60]}…/ is gone or reworded — fix its shape, do not drop it" if m.nil?

      periodic_anchors += 1
      m.captures.zip(values).each do |quoted, value|
        flag(failures, "periodic derivation «#{m[0][0, 70]}…»", render.call(value, quoted), quoted) if render.call(value, quoted) != quoted
      end
    end
    # The words the numbers stand under, held to the numbers — each word in a regex above, each claim here:
    lo, hi = ladder["rows"].map { |r| r["axial_ratio"] }.minmax
    failures << "periodic /16 E[100] #{equal16['E100']} is not inside the cube ladder #{lo}–#{hi}, as canon says" unless equal16["E100"].between?(lo, hi)
    failures << "«на всіх N парах»: the deviatoric gap does not keep one sign over every pair; #{dev_gap}" unless dev_gap.all?(&:negative?) || dev_gap.all?(&:positive?)
    # «не встановлює» holds while the pairs disagree in sign OR a raw part row, carried to each density-matched rung's
    # density by the canonical n, reads against some rung with the sign the bases do not have (the bases are extrapolations
    # a non-monotone sweep does not prove — 2026-10-22, HW.33). DENSITY-MATCHED only: the first form of this check set a raw
    # row at 63.96 % porosity against the whole ladder at 62.9–64.7 % — the very unmatched comparison the same canon
    # paragraph refuses for the equal step (RA1 review of b8bbf08fb, 2026-10-22).
    raw_across = n_pair && sweep["rows"].any? { |r| raw_gaps.call(r).any? { |x| axial_gap.max.negative? ? x.positive? : x.negative? } }
    failures << "«знака розриву драбина не встановлює»: the axial gap keeps ONE sign over the pairs and no density-matched raw part row reads the other sign — canon must say which; #{axial_gap}" unless (axial_gap.min.negative? && axial_gap.max.positive?) || raw_across
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

# ── 10. THE STATIC (TRACTION) IN-PLANE READING (§5.2, HW.23 — 2026-10-28) ───────────────────────────────────────────
#
# 🔴 Added with `fea --traction`, for the reason layers 4, 5 and 8 exist: the numbers live in a file family
# (`*.traction.h*um.json`) no other layer opens. Held: (a) TRANSCRIPTION of every cell — the three moduli, the porosity,
# the ⟨σ⟩_dd and projection ranges (printed OUTWARD: the low end down, the high end up) and the alternative
# equilibration at every angle; (b) PROVENANCE — the file calls itself STATIC, is the pine part at the sweep's ν, its
# solid counterpart reads 1, every row and its alternative converged, the support reaction sits at solver precision, the
# reading's correction stayed on the loaded nodes, and ⟨σ⟩'s off-axis share is under the bound canon QUOTES (read from
# canon, never typed here); (c) the SET of steps — every cache has exactly one table row and every row a cache (a step
# run without the table, a row duplicated over another, a rewording that disarms the row shape — each reds); (d) the
# DERIVED sentences, each COMPOSED here from the caches and `105`'s two readings and required verbatim in canon — where
# the reading lies per angle, which way the alternative equilibration moves it per angle, the margins of every angle
# that sits between the readings, and the step transcription (finest against coarsest — a transcription, never a trend); and `105`'s own premise categories agree with this layer's.
# ⛔ DECLARED CEILING: it pins the numbers and the sentences canon reads off them, never the instrument (VoxelFeaTests
# holds the closed forms), nor whether the named form is the right static condition, nor on which side of the true
# static modulus the reading sits — that is the reading canon names, ceiling (3).
traction_files = Dir.glob(File.join(ROOT, "tools/cad/cache/fea/anchor_zone1_pine.traction.h*um.json")).sort
traction_rows_seen = 0
traction_anchors = 0
if traction_files.empty?
  failures << "the traction caches are not committed — canon §5.2 quotes them (`fea --traction`)" if canon.include?("#### Статичний (силовий)")
else
  tr = traction_files.map { |f| JSON.parse(File.read(f)) }.sort_by { |d| -d["step_mm"] }
  c105 = JSON.parse(File.read(CACHE_105))
  lo105, hi105 = c105["inputs"]["fe_readings"].values.minmax
  thetas = [ 0.0, 22.5, 45.0 ]
  at = ->(d, th) { d["rows"].find { |r| (r["theta_deg"] - th).abs < 1e-9 } }
  e_of = ->(d, th) { at.call(d, th)["traction_modulus_ratio"] }
  alt_of = ->(d, th) { at.call(d, th)["all_nodes_equilibration_ratio"] }
  off_bound = canon[/[Чч]астка ⟨σ⟩ поза віссю — ≤ ([0-9.]+) %/, 1]
  failures << "traction: canon no longer quotes the off-axis bound «частка ⟨σ⟩ поза віссю — ≤ X %»" if off_bound.nil?
  tr.each do |d|
    tag = "traction #{format('%.4f', d['step_mm'])} mm"
    failures << "#{tag}: the file does not call itself STATIC" unless d["_note"].to_s.include?("STATIC")
    failures << "#{tag}: not the pine part at the sweep's ν" unless d["cem"] == "anchor_zone1_pine" && (d["poisson_ratio"] - sweep["poisson_ratio"]).abs < 1e-12
    failures << "#{tag}: solid calibration #{d['solid_calibration_theta0']}, not 1" unless (d["solid_calibration_theta0"] - 1.0).abs < 1e-6
    failures << "#{tag}: angles #{d['rows'].map { |r| r['theta_deg'] }} — canon reads #{thetas}" unless d["rows"].map { |r| r["theta_deg"].to_f } == thetas
    d["rows"].each do |r|
      th = "#{tag} θ #{r['theta_deg']}"
      failures << "#{th}: did not converge — canon must not quote it" unless r["converged"]
      failures << "#{th}: the alternative equilibration did not converge" unless r["all_nodes_equilibration_converged"] == true
      failures << "#{th}: support reacted #{r['support_reaction_relative']}" unless r["support_reaction_relative"] < 1e-5
      failures << "#{th}: the correction left the loaded nodes (#{r['load_outside_loaded_relative']})" unless r["load_outside_loaded_relative"].to_f < 1e-12 && r.key?("load_outside_loaded_relative")
      if off_bound && r["macro_stress_off_axis_relative"] * 100.0 > off_bound.to_f
        failures << "#{th}: ⟨σ⟩ off uniaxial by #{format('%.2f', r['macro_stress_off_axis_relative'] * 100.0)} % — canon says ≤ #{off_bound} %"
      end
    end
  end
  if off_bound
    want = format("%.1f", (tr.flat_map { |d| d["rows"].map { |r| r["macro_stress_off_axis_relative"] } }.max * 1000.0).ceil / 10.0)
    flag(failures, "traction off-axis bound (rounded UP from the largest row)", want, off_bound) if want != off_bound
  end
  down = ->(x, n) { (x * 10**n).floor.to_f / 10**n }
  up = ->(x, n) { (x * 10**n).ceil.to_f / 10**n }
  dens = []
  canon.scan(/^\| 11\/(\d+) \(([0-9.]+) мм\) \| ([0-9.]+) % \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+) \| ([0-9.]+)–([0-9.]+) \| (\d+)–(\d+) % \| ([0-9.]+) · ([0-9.]+) · ([0-9.]+) \|$/) do
    den, mm, por, e0, e22, e45, s_lo, s_hi, p_lo, p_hi, a0, a22, a45 = Regexp.last_match.captures
    dens << den
    d = tr.find { |x| (x["step_mm"] - (11.0 / den.to_i)).abs < 1e-6 }
    next failures << "traction table row 11/#{den} has no cache file" if d.nil?

    traction_rows_seen += 1
    s = d["rows"].map { |r| r["macro_stress_along_d"] }
    pr = d["rows"].map { |r| r["projection_relative"] * 100.0 }
    expect = { "step" => [ format("%.4f", d["step_mm"]), mm ], "porosity" => [ format("%.1f", d["porosity"] * 100.0), por ],
               "⟨σ⟩ low" => [ format("%.2f", down.call(s.min, 2)), s_lo ], "⟨σ⟩ high" => [ format("%.2f", up.call(s.max, 2)), s_hi ],
               "projection low" => [ pr.min.floor.to_s, p_lo ], "projection high" => [ pr.max.ceil.to_s, p_hi ] }
    thetas.zip([ e0, e22, e45 ], [ a0, a22, a45 ]).each do |th, e, a|
      expect["θ#{th}"] = [ format("%.4f", e_of.call(d, th)), e ]
      expect["all-nodes θ#{th}"] = [ format("%.4f", alt_of.call(d, th)), a ]
    end
    expect.each { |cell, (want, got)| flag(failures, "traction 11/#{den} #{cell}", want, got) if want != got }
  end
  failures << "traction table rows #{dens.tally.select { |_, n| n > 1 }.keys} appear more than once" if dens.uniq.size < dens.size
  if traction_rows_seen < tr.size || dens.uniq.size < tr.size
    failures << "only #{dens.uniq.size} distinct traction rows for #{tr.size} cache files — a step was run without the table, "\
                "a row was duplicated over another, or a rewording DISARMED the comparison; fix the row shape, do not lower this number"
  end

  # (d) the sentences, composed from the caches — never typed here
  ang = ->(th) { th.zero? ? "θ = 0" : "θ = #{format('%g', th)}°" }
  list = lambda do |ths|
    xs = ths.map { |th| ang.call(th) }
    xs.empty? ? "ні на якому куті" : (xs.size < 3 ? xs.join(" і ") : "#{xs[0..-2].join(', ')} і #{xs[-1]}")
  end
  where = thetas.group_by do |th|
    es = tr.map { |d| e_of.call(d, th) }
    es.min >= hi105 ? :above : (es.max < lo105 ? :below : :between)
  end
  where_text = "вище обох — на #{list.call(where.fetch(:above, []))}; між ними — на #{list.call(where.fetch(:between, []))}; "\
               "нижче обох — на #{list.call(where.fetch(:below, []))}"
  readings_text = "(нижчого #{format('%.4f', lo105)} і вищого #{format('%.4f', hi105)})"
  move = thetas.group_by do |th|
    ds = tr.map { |d| alt_of.call(d, th) - e_of.call(d, th) }
    ds.all?(&:negative?) ? :down : (ds.all?(&:positive?) ? :up : :mixed)
  end
  move_text = { down: "вниз на кожному кроці", up: "вгору на кожному кроці", mixed: "у різні боки по кроках" }
              .filter_map { |k, w| "#{w} — на #{list.call(move[k])}" if move[k] }.join("; ")
  pct = ->(x) { format("%+.1f", x * 100.0).sub("-", "−") + " %" }
  fine = tr.last
  margins = where.fetch(:between, []).map do |th|
    "на #{ang.call(th)} на найдрібнішому кроці прочитання стоїть на #{pct.call(e_of.call(fine, th) / lo105 - 1.0)} від нижчого "\
      "FE-прочитання і на #{pct.call(e_of.call(fine, th) / hi105 - 1.0)} від вищого, а альтернативне врівноваження зсуває "\
      "його на #{pct.call(alt_of.call(fine, th) / e_of.call(fine, th) - 1.0)}"
  end
  sentences = { "where the reading lies per angle" => "#{readings_text} на кожному виміряному кроці: #{where_text}",
                "which way the alternative equilibration moves it" => "поправка по всіх вузлах зсуває прочитання #{move_text}" }
  margins.each_with_index { |m, i| sentences["the margins of a between-angle (#{i + 1})"] = m }
  coarse, = tr
  dd = thetas.map { |th| e_of.call(fine, th) <=> e_of.call(coarse, th) }.uniq
  word = { [ -1 ] => "менше", [ 1 ] => "більше" }.fetch(dd, "по-різному")
  den_of = ->(d) { (11.0 / d["step_mm"]).round }
  sentences["the step transcription (finest against coarsest, every angle)"] =
    "На кожному куті число на 11/#{den_of.call(fine)} #{word}, ніж на 11/#{den_of.call(coarse)}"
  sentences.each do |what, s|
    traction_anchors += 1
    failures << "traction: canon no longer carries #{what}, composed from the caches: «#{s}»" unless canon.include?(s)
  end
  p105 = c105.fetch("gyroid_bound_premise_static_modulus", {}).fetch("by_theta", {})
  thetas.each do |th|
    mine = where.find { |_, ths| ths.include?(th) }.first
    theirs = { "above_both" => :above, "below_both" => :below, "between" => :between }[p105.dig(format("%g", th), "where")]
    failures << "traction: `105` files #{ang.call(th)} as #{theirs.inspect}, this layer as #{mine.inspect} — re-run `105`" unless mine == theirs
  end
  failures << "traction: the higher reading #{hi105} is not above the lower #{lo105} — «обидва FE-прочитання» names two" unless hi105 > lo105
end

if failures.empty?
  puts "fea_canon_sync ✓ — 01_01 §5.2 matches tools/cad/cache/fea (transcription + #{anchors} derivation anchors + provenance " \
       "+ #{fit_rows_seen} fitted rows + #{dilation_rows_seen} sensitivity rows and #{dilation_anchors} of their derivations, " \
       "zero row = the pinned sweep field for field, + the graded pair of §5.5, + the canonical pair as quoted #{pair_quotes}× " \
       "and #{pair_derivations} derivations with it, + #{gap_anchors} size-gap derivations, + #{periodic_rows_seen} periodic-tensor rows and #{periodic_anchors} of " \
       "their derivations, + #{traction_rows_seen} static-reading rows and #{traction_anchors} of their derivations)"
  exit 0
end

warn "fea_canon_sync ✗ — canon §5.2 has drifted from the FE cache:"
failures.each { |f| warn "  · #{f}" }
warn "\nFix at the HOME (the cache is the measurement; canon quotes it) — re-run `dotnet run -- fea … --sweep`"
warn "and `fea --ladder` if the geometry moved, or correct the canon sentence if only the prose drifted."
exit 1
