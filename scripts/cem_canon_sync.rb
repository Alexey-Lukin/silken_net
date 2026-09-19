#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# CEM↔canon geometry drift guard (HW.33 anchor-geometry audit; sibling of DocsLinter.anchor_dimension_drift).
# HARD gate, wired into docs.yml (promoted from advisory once green). Pure Ruby stdlib (json) — no .NET,
# no conda → CI-safe.
#
# The shipped `tools/cad/cem/*.json` geometry numbers are a MIRROR of their canon owner (01_01/01_02/01_04);
# this guard pins each against its canon anchor, CONTEXT-ANCHORED (regex on the surrounding label, never a
# bare number) — the Ruby sibling of the §01b `test_doc_cache_sync.py`.
#
# Why it exists (what already bit, §01a vilize 2026-07-14):
#   • the C# golden xUnit validates the C#-record DEFAULTS, not the shipped json (RadomeTests parses a
#     minimal {kind,name}) — that half is STRUCTURAL and still true: a shipped json can drift with the
#     xUnit staying green. ⚠️ Its illustration is HISTORICAL and must not be read as a live finding:
#     MechanicalLockTests.MkCem once pinned the OFF-SPEC groove 0.8×0.6 against the shipped DIN-471
#     1.1×0.25, and THIS COMMIT (c52b03b7) repaired it — the test now pins 1.1/0.25, as does canon
#     §4.3. Re-measured 2026-09-09 (HW.45): the motive died, the ground did not (00_05 §5).
#   • the same axis has a THIRD home this guard does NOT reach: where a manifest omits a field, the
#     EFFECTIVE geometry is the C#-record default in Cem.cs, bound to canon by nothing. Measured
#     2026-09-09: 14 such fields, all in the assembly-level manifests, and the sharpest are the ones
#     that cross machine halves — o_ring_gap_mm 1.424f was DERIVED from in-silico script 52
#     (ORING_CS 1.78 × 0.80; the field left the record with branch (а), 2026-09-14),
#     rf_clearance_min_mm 12f mirrors 02_01 §5.3, and zone1_insertion_mm 30
#     carries no provenance comment at all.
#     🔴 «All correct today» stood here as the GROUND of the refusal and FELL 2026-09-11 on that very
#     example: 02_01 §5.3 requires ≥ 8 mm (10–15 desirable, λ/40 = 8.6, HFSS mandatory below 10), and
#     its only 12 is the OUTCOME of a proposed two-deck board stack. So rf_clearance_min_mm mirrors a
#     design POINT as a floor, and the true set was never empty — the 2026-09-09 audit checked each
#     field's ADDRESS (does §5.3 exist and speak about this) and never its CLAUSE (does §5.3 require
#     this number). The same miss is why the in-silico half carries the identical 12.
#     ⛔ The REFUSAL still stands and is NOT overturned here — it is ⚖️ founder-ratified (00_07 §🗄️
#     HW.45), and one wrong field is an instance to fix, not a class to gate (00_05 §5: when the
#     measurement shrinks a «class» to one or two instances, treat the instances). Do not rebuild the
#     pin on this note alone. What DID change is the price: it is no longer «a hypothetical future
#     copy reds nothing» but «a live one already did», so the carriers (picogk + in-silico skills,
#     both patched 2026-09-11) are now load-bearing rather than precautionary, and re-opening the
#     verdict is founder's call — the measurement lives in 02_01 §5.3 (the 2026-09-11 limitation note).
#   • DocsLinter.anchor_dimension_drift only catches prose RANGES (20-30 flange / 40-60 Zone-2), never a
#     cem value.  • bell_radius_mm=5.0 had NO assert anywhere.
# So a shipped cem number could drift from canon with zero gate. This closes that.
#
# Modes: :eq  cem == canon stated value (± tol)  ·  :ge  cem >= canon minimum (for "≥ N" constraints).

require "json"

REPO = File.expand_path("..", __dir__)
CEM_DIR = File.join(REPO, "tools/cad/cem")

def load_cem(file) = JSON.parse(File.read(File.join(CEM_DIR, file)))
def load_canon(file) = File.read(File.join(REPO, "docs", file))
def dig_num(hash, path) = path.split(".").reduce(hash) { |acc, k| acc.fetch(k) }.to_f

C1 = "01_01_Coaxial_Gyroid_Topology_and_PEEK.md"
C4 = "01_04_CODIT_and_Xylemointegration.md"
C22 = "02_02_Blind_Mate_Pogo_Pin_Interface.md"

# [label, cem-file, json-path, canon-doc, /regex ONE capture/, mode, tol, (scale = 1)]
# `scale` multiplies the CEM value before the comparison — the gland squeeze is a FRACTION in the manifest and a
# PERCENT in canon prose, and neither home should have to spell the other's unit.
CHECKS = [
  # ── §4.3 mechanical-lock barb working-point (over-specified tooth: pin h + α/β, base is derived) ──
  [ "barb height h", "mechanical_lock.zone1.json", "barb_height_mm",
   C1, /Робоча точка \*\*h = ([\d.]+)\*\*/, :eq, 0.001 ],
  [ "barb lead-angle α", "mechanical_lock.zone1.json", "lead_angle_deg",
   C1, /leading-edge α = (\d+)°/, :eq, 0.5 ],
  [ "barb trail-angle β", "mechanical_lock.zone1.json", "trail_angle_deg",
   C1, /trailing-edge β = (\d+)°/, :eq, 0.5 ],
  # ── §1.4 monolithic bus (rod Ø1.0 / channel Ø1.35 / liner 0.15) ──
  # ⚠️ The channel read Ø1.3 in this heading until 2026-09-11, a day after the verdict opened it to 1.35
  # (`00_07` HW.34). The ASSERT below was never wrong — it reads the number out of canon — so the gate
  # stayed green and true while the only stale text was the line a HUMAN reads before touching the dim.
  # Reflex: a guard's heading is documentation, not code, and nothing verifies it; move it with the value.
  # ⚠️ The anchor moved with the WELDED branch (2026-09-18): canon says «дріт шини» now, because the rod
  # is no longer printed with the anode. The VALUE is unchanged — this row reads the wire Ø, which the
  # stack still consumes (F3/F4) and the sheet still prints as an assembly dimension (00_07 HW.1).
  [ "bus wire Ø (§1.4)", "anchor_zone1.pine.json", "bus_rod_diameter_mm",
   C1, /дріт шини \*\*Ø([\d.]+) мм\*\*/, :eq, 0.001 ],
  [ "cathode bus channel Ø (§1.4)", "cathode_flange.json", "bore_diameter_mm",
   C1, /катодний канал \*\*Ø([\d.]+) мм\*\*/, :eq, 0.001 ],
  [ "bus liner (§1.4)", "cathode_flange.json", "bus_liner_thickness_mm",
   C1, /lining \*\*([\d.]+) мм\*\*/, :eq, 0.001 ],
  # ── §5.5-A anti-overgrowth bell (≥ constraints — the bell_radius that had NO assert) ──
  [ "radome bell-rise ≥ (§5.5)", "radome.json", "bell_rise_mm",
   C4, /Виступ ≥ (\d+) мм/, :ge, 0.0 ],
  [ "radome bell-radius ≥ (§5.5)", "radome.json", "bell_radius_mm",
   C4, /Радіус заокруглення ≥ (\d+) мм/, :ge, 0.0 ],
  # ── §4.3 B DIN-471 groove (THE drift this guard was born for: canon §3 = §4.3 B = C#-default = json) ──
  [ "lock groove width (§4.3 B DIN-471 Ø11)", "mechanical_lock.zone1.json", "groove_width_mm",
   C1, /Ø11 → width ≈ ([\d.]+) mm × depth/, :eq, 0.001 ],
  [ "lock groove depth (§4.3 B DIN-471 Ø11)", "mechanical_lock.zone1.json", "groove_depth_mm",
   C1, /width ≈ 1\.1 mm × depth ≈ ([\d.]+) mm/, :eq, 0.001 ],
  # ── 02_02 §3.2 O-ring gland (branch (а), applied 2026-09-14): the cord and the ratified squeeze the flange
  #    groove is DERIVED from. Pinned on the flange (it cuts the groove); the radome's copy is pinned equal to it
  #    by xUnit (RadomeTests), so one canon anchor covers both halves. The gland FILL joined 2026-09-19: until
  #    ⚖️ 2026-09-17 it was deliberately NOT pinned, because canon carried no number of its own and would only
  #    have quoted the manifest back; the verdict gave canon the number, and with it the reason for the pin. ──
  [ "O-ring cord CS (§3.2)", "cathode_flange.json", "o_ring.cs_mm",
   C22, /Переріз \(CS\) \| \*\*([\d.]+) мм\*\*/, :eq, 0.001 ],
  [ "O-ring ratified squeeze nominal (§3.2 mirror of §3.5)", "cathode_flange.json", "o_ring.squeeze",
   C22, /Ступінь стиснення \| [^|]*номінал \*\*([\d.]+) %\*\*/, :eq, 0.01, 100.0 ],
  [ "O-ring ratified gland fill (§3.2)", "cathode_flange.json", "o_ring.gland_fill",
   C22, /заповнення \*\*([\d.]+) %\*\* — ⚖️ РАТИФІКОВАНО/, :eq, 0.01, 100.0 ]
]

failures = []
CHECKS.each do |label, cem_file, path, doc_file, regex, mode, tol, scale|
  hits = load_canon(doc_file).scan(regex).flatten
  if hits.size != 1
    failures << "[#{label}] canon anchor matched #{hits.size} (need exactly 1) — reworded? regex=#{regex.source}"
    next
  end
  canon_val = hits[0].to_f
  cem_val = dig_num(load_cem(cem_file), path) * (scale || 1.0)
  ok = mode == :ge ? cem_val >= canon_val - tol : (cem_val - canon_val).abs <= tol
  next if ok

  failures << "[#{label}] CEM↔CANON DRIFT: #{cem_file}##{path} = #{cem_val} vs canon " \
              "#{mode == :ge ? '≥ ' : ''}#{canon_val} (#{doc_file}) — cem mirrors canon; fix at the home."
end

if failures.empty?
  puts "cem↔canon geometry: all #{CHECKS.size} pinned dims match canon ✓"
  exit 0
end
warn "cem↔canon geometry DRIFT (#{failures.size}/#{CHECKS.size}):"
failures.each { |f| warn "  #{f}" }
exit 1
