#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# FIELDS ⟷ canon sync gate (OPS.6 durable guard).
#
# `GithubBootstrap::FIELDS` is the code-SSOT of the Projects V2 schema and
# docs/00_05 §1.1 is its canon table — and they drifted silently for weeks:
# `CLUSTER_OPTIONS` kept `Cross-cluster` 37 days after canon retired it, and
# the spec ASSERTED the stale option (a golden test locking the wrong value —
# the cem_canon_sync class). NO spec in the repo read canon until 2026-07-16;
# this gate makes the row-scoped comparison permanent.
#
# Row policies (curated tripwire — a NEW §1.1 row without a policy fails):
#   :trl        — options are exactly TRL:1..TRL:9 (the "1-9, never 10-12"
#                 invariant, 00_02 §1);
#   :closed     — canon lists the FULL option set → exact ordered equality
#                 (slash-families like `MRL:8/9/10` expand);
#   :labels_yml — canon row is an ellipsis; the closed set lives in
#                 .github/labels.yml `module:NN-slug` (00_05 §4.4) → compare
#                 normalized ("04: Server Core" ≡ module:04-server-core);
#   :prefix     — time-bounded seed lists (Cycle/Semester): canon-listed
#                 options must be a PREFIX of the code list, in order (the
#                 `Fall 2025-2026`-missing class);
#   :text_only  — no options (type check still applies).
#
# Pure Ruby (stdlib only — github_bootstrap.rb needs no Rails). Run:
#   ruby scripts/field_canon_sync.rb
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.

require "yaml"
require_relative "../lib/github_bootstrap"

ROOT       = File.expand_path("..", __dir__)
CANON      = File.join(ROOT, "docs/00_05_GitHub_Projects_and_IaC_Automation.md")
LABELS_YML = File.join(ROOT, ".github/labels.yml")

ROW_POLICY = {
  "Current TRL"       => :trl,
  "Target TRL"        => :trl,
  "Readiness Horizon" => :closed,
  "Assigned Agent"    => :closed,
  "Module"            => :labels_yml,
  "Appetite"          => :closed,
  "SSOT Link"         => :text_only,
  "R&D Cluster"       => :closed,
  "Shape Up Stage"    => :closed,
  "Cycle"             => :prefix,
  "Academic Semester" => :prefix
}.freeze

# ── parse the §1.1 table: name → {type:, options:[canon-listed]} ────────────
lines = File.readlines(CANON)
start = lines.index { |l| l.start_with?("### ") && l.include?("1.1 Custom Fields") } or
  abort("field_canon_sync: cannot locate §1.1 in 00_05")
rest  = lines[(start + 1)..]
stop  = rest.index { |l| l.start_with?("#") } || rest.size
rows  = rest[0...stop].select { |l| l.lstrip.start_with?("|") }
        .reject { |l| l.include?("Поле") || l.match?(/\A\|\s*:?-/) }

canon_fields = rows.to_h do |row|
  cells = row.split("|")[1..].map(&:strip)
  name  = cells[0].gsub("**", "")
  desc  = cells[2].to_s
  desc  = desc.split("*(").first.to_s               # cut historical parenthetical
  desc  = desc.gsub(/\[([^\]]*)\]\([^)]*\)/, "")    # strip doc-links (their labels are refs, not options)
  opts  = desc.scan(/`([^`]+)`/).flatten
              .flat_map { |s| s.match?(%r{\A([A-Za-z]+:)\d+(/\d+)+\z}) ? s.split(":").last.split("/").map { |n| "#{s.split(':').first}:#{n}" } : [ s ] }
  [ name, { type: cells[1], options: opts } ]
end

code_fields = GithubBootstrap::FIELDS.to_h { |f| [ f[:name], f ] }
errors = []

# ── 1:1 names + order ───────────────────────────────────────────────────────
if canon_fields.keys != code_fields.keys
  (canon_fields.keys - code_fields.keys).each { |n| errors << "поле у §1.1, але не у FIELDS: #{n.inspect}" }
  (code_fields.keys - canon_fields.keys).each { |n| errors << "поле у FIELDS, але не у §1.1: #{n.inspect}" }
  if (canon_fields.keys - code_fields.keys).empty? && (code_fields.keys - canon_fields.keys).empty?
    errors << "порядок полів §1.1 ≠ порядок FIELDS (order matters — stable diffs)"
  end
end
(canon_fields.keys - ROW_POLICY.keys).each { |n| errors << "новий §1.1-рядок без ROW_POLICY: #{n.inspect}" }
(ROW_POLICY.keys - canon_fields.keys).each { |n| errors << "мертвий ROW_POLICY-запис (рядка нема в §1.1): #{n.inspect}" }

# ── per-row type + options ──────────────────────────────────────────────────
canon_fields.each do |name, canon|
  code = code_fields[name] or next
  expected_type = canon[:type].casecmp?("Text") ? :text : :single_select
  errors << "#{name}: тип §1.1 «#{canon[:type]}» ≠ код :#{code[:type]}" unless code[:type] == expected_type

  case ROW_POLICY[name]
  when :trl
    want = (1..9).map { |n| "TRL:#{n}" }
    errors << "#{name}: опції ≠ TRL:1..TRL:9 (інваріант «1-9, ніколи 10-12»)" unless code[:options] == want
  when :closed
    errors << "#{name}: §1.1 #{canon[:options].inspect} ≠ код #{code[:options].inspect}" unless canon[:options] == code[:options]
  when :labels_yml
    labels = YAML.safe_load_file(LABELS_YML).filter_map { |l| l["name"][/\Amodule:(.+)\z/, 1] }
    norm   = code[:options].map { |o| o.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "") }
    errors << "#{name}: MODULE_OPTIONS ≉ закрита дев'ятка labels.yml (#{(norm - labels) + (labels - norm)})" unless norm.sort == labels.sort
  when :prefix
    listed = canon[:options].select { |o| code[:options].any? { |c| c == o } || o.match?(/\A(Cycle |Fall |Spring )/) }
    errors << "#{name}: §1.1-перелік #{listed.inspect} не є префіксом коду #{code[:options].inspect}" unless code[:options].first(listed.size) == listed
    if name == "Cycle" && (bad = code[:options].reject { |o| o.match?(/\ACycle \d{4}\.Q[1-4]\z/) }).any?
      errors << "Cycle: опції поза форматом `Cycle YYYY.QN`: #{bad.inspect}"
    end
  when :text_only
    errors << "#{name}: text-поле не має нести options" if code[:options]
  end
end

# ── report ──────────────────────────────────────────────────────────────────
if errors.empty?
  puts "field_canon_sync ✓ — 00_05 §1.1 ⟷ GithubBootstrap::FIELDS (#{code_fields.size} полів, " \
       "#{code_fields.values.sum { |f| Array(f[:options]).size }} опцій, module-дев'ятка ⟷ labels.yml)"
  exit 0
else
  warn "field_canon_sync ✗ — FIELDS ↔ канон drift (OPS.6):"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
