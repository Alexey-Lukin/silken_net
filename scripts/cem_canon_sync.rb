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
#     minimal {kind,name}); worse, MechanicalLockTests.MkCem pins the OFF-SPEC groove 0.8×0.6 while the
#     shipped json carries the corrected DIN-471 1.1×0.25 — the golden test LOCKS THE WRONG number.
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

# [label, cem-file, json-path, canon-doc, /regex ONE capture/, mode, tol]
CHECKS = [
  # ── §4.3 mechanical-lock barb working-point (over-specified tooth: pin h + α/β, base is derived) ──
  [ "barb height h", "mechanical_lock.zone1.json", "barb_height_mm",
   C1, /Робоча точка \*\*h = ([\d.]+)\*\*/, :eq, 0.001 ],
  [ "barb lead-angle α", "mechanical_lock.zone1.json", "lead_angle_deg",
   C1, /leading-edge α = (\d+)°/, :eq, 0.5 ],
  [ "barb trail-angle β", "mechanical_lock.zone1.json", "trail_angle_deg",
   C1, /trailing-edge β = (\d+)°/, :eq, 0.5 ],
  # ── §1.4 monolithic bus (rod Ø1.0 / channel Ø1.3 / liner 0.15) ──
  [ "bus rod Ø (§1.4)", "anchor_zone1.pine.json", "bus_rod_diameter_mm",
   C1, /стрижень \*\*Ø([\d.]+) мм\*\*/, :eq, 0.001 ],
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
   C1, /width ≈ 1\.1 mm × depth ≈ ([\d.]+) mm/, :eq, 0.001 ]
]

failures = []
CHECKS.each do |label, cem_file, path, doc_file, regex, mode, tol|
  hits = load_canon(doc_file).scan(regex).flatten
  if hits.size != 1
    failures << "[#{label}] canon anchor matched #{hits.size} (need exactly 1) — reworded? regex=#{regex.source}"
    next
  end
  canon_val = hits[0].to_f
  cem_val = dig_num(load_cem(cem_file), path)
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
