#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/coverage_seed_diff.rb — полювання на seed-залежний coverage-флак
# (TEST.1: «кілька line/branch плавають між прогонами; точний hunt = diff
# двох fixed-seed прогонів»). Порівнює два SimpleCov `.resultset.json` і
# репортує рядки/гілки, чия ПОКРИТІСТЬ (covered vs uncovered) різниться —
# тобто код, який вправляється лише за певного ПОРЯДКУ тестів (memoization
# first-test-wins, class-level стан, time-window гілки). Read-only.
#
# Рецепт зняття пари resultset'ів (SimpleCov мержить у 10-хв вікні —
# обов'язково чистити .resultset.json МІЖ прогонами):
#   rm -f coverage/.resultset.json && bin/rspec --seed 11111 && \
#     cp coverage/.resultset.json /tmp/a.json
#   rm -f coverage/.resultset.json && bin/rspec --seed 22222 && \
#     cp coverage/.resultset.json /tmp/b.json
#   ruby scripts/coverage_seed_diff.rb /tmp/a.json /tmp/b.json
#
# Канон-дім політики гейту/маржі — 04_06 §B.3; тріаж знахідок — §B.4.

require "json"

abort "usage: #{$PROGRAM_NAME} A.resultset.json B.resultset.json" unless ARGV.size == 2

def load_resultset(path)
  raw = JSON.parse(File.read(path))
  suite = raw.values.first or abort "#{path}: порожній resultset"
  suite.fetch("coverage")
end

a, b = ARGV.map { |p| load_resultset(p) }
root = File.expand_path("..", __dir__) + "/"

line_floats   = [] # [file, line_no, covered_in_a, covered_in_b]
branch_floats = [] # [file, branch_key, covered_in_a, covered_in_b]

(a.keys | b.keys).sort.each do |file|
  fa = a[file]
  fb = b[file]
  unless fa && fb
    warn "⚠ файл лише в одному прогоні: #{file.delete_prefix(root)}"
    next
  end

  la = fa["lines"] || []
  lb = fb["lines"] || []
  warn "⚠ різна довжина lines: #{file.delete_prefix(root)}" if la.size != lb.size
  [ la.size, lb.size ].min.times do |i|
    ca = la[i]
    cb = lb[i]
    next if ca.nil? || cb.nil?               # nil = нерелевантний рядок
    next if (ca.positive?) == (cb.positive?) # однакова покритість — не флак
    line_floats << [ file.delete_prefix(root), i + 1, ca, cb ]
  end

  ba = fa["branches"] || {}
  bbr = fb["branches"] || {}
  (ba.keys | bbr.keys).each do |cond|
    ha = ba[cond] || {}
    hb = bbr[cond] || {}
    (ha.keys | hb.keys).each do |branch|
      ca = ha[branch]
      cb = hb[branch]
      next if ca.nil? || cb.nil?
      next if (ca.positive?) == (cb.positive?)
      branch_floats << [ file.delete_prefix(root), branch, ca, cb ]
    end
  end
end

puts "── seed-flake coverage diff ──"
puts "line-флоатери:   #{line_floats.size}"
line_floats.each { |f, l, ca, cb| puts "  #{f}:#{l}  A=#{ca} B=#{cb}" }
puts "branch-флоатери: #{branch_floats.size}"
branch_floats.each { |f, br, ca, cb| puts "  #{f}  #{br}  A=#{ca} B=#{cb}" }
puts "(порожньо = покритість детермінована щодо порядку тестів)" if line_floats.empty? && branch_floats.empty?
