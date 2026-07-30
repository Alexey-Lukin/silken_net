#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# PR auto-labeler config gate (OPS.3 durable guard) — .github/labeler.yml.
#
# CHECK A — a negative glob may never be a SELF-SUFFICIENT branch.
#   actions/labeler defaults every matcher LIST to `any:` (OR): the top-level
#   list under a label, the list under `any:`, the matchers under one
#   `changed-files`, and the globs inside an `any-glob-*` matcher. A negative
#   glob (`!app/services/iotex/**`) matches every file OUTSIDE the excluded
#   subtree — so the moment it can satisfy a label on its own, that label
#   sticks to essentially every PR. This was LIVE here: `cluster:C-scaling`
#   labelled all PRs until 2026-07-16 (canon 00_05 §2.6).
#
#   The check is NOT "is there an `all:` above it" — that phrasing passes two
#   real holes: a negative sharing one `changed-files` list with a positive
#   (OR *inside* the AND-wrapper), and an `all:` holding the negative block
#   ALONE. So the rules are expanded into a disjunction of conjunctions
#   (OR nodes union, AND nodes cartesian-product) and every branch carrying a
#   negative glob must also carry a positive one. Branches are deduped to the
#   (has-positive, negatives) pair, which keeps the product from blowing up.
#
# CHECK B — every labeler key exists in .github/labels.yml (Labels-as-Code
#   SSOT, 00_05 §4). A phantom key is silently inert: labeler creates nothing,
#   so the routing rule simply never fires. Real class — the canon mirror
#   carried `module:06-infra` while the live label was `module:06-matrix`.
#   One-directional BY DESIGN: labels.yml is wider (type:*, priority:*,
#   hand-applied triage markers), so the reverse direction would be noise.
#
# Ceiling — what this gate does NOT see. It checks FORM, not INTENT: a
# correctly AND-wrapped negative can still exclude the wrong subtree, and
# routing-coverage ("every path owns a primary cluster", 00_05 §4.1) stays an
# eyes-on audit. It also cannot verify a rule against a live PR — GitHub
# freezes the `pull_request_target` payload, so `gh run rerun` does NOT re-read
# the config; only a fresh event does.
#
# Pure Ruby (stdlib only). Run:
#   ruby scripts/labeler_config_check.rb
# Exit 0 = clean; exit 1 = drift. Method/why → docs/00_06 §3.

require "yaml"

ROOT       = File.expand_path("..", __dir__)
LABELER    = File.join(ROOT, ".github/labeler.yml")
LABELS_YML = File.join(ROOT, ".github/labels.yml")

OR_GLOB_KEYS  = %w[any-glob-to-any-file any-glob-to-all-files].freeze   # OR across globs
AND_GLOB_KEYS = %w[all-globs-to-any-file all-globs-to-all-files].freeze # AND across globs
BRANCH_KEYS   = %w[base-branch head-branch].freeze

NEUTRAL = { pos: false, neg: [] }.freeze

errors = []

def merge(a, b)
  { pos: a[:pos] || b[:pos], neg: (a[:neg] + b[:neg]).uniq }
end

# AND across a list of branch-sets → cartesian product (deduped).
def and_product(sets)
  sets.reduce([ NEUTRAL ]) do |acc, set|
    acc.product(set).map { |x, y| merge(x, y) }.uniq
  end
end

def leaf(glob)
  glob.to_s.lstrip.start_with?("!") ? { pos: false, neg: [ glob.to_s ] } : { pos: true, neg: [] }
end

# A match-object Hash → its branches. Keys of one Hash are AND-ed.
def branches_of(node, label, errors)
  unless node.is_a?(Hash)
    errors << "#{label}: матч-об'єкт не Hash (#{node.inspect}) — правило непарсибельне"
    return [ NEUTRAL ]
  end
  and_product(node.map { |key, value| branches_of_key(key, value, label, errors) })
end

def branches_of_key(key, value, label, errors)
  case key
  when "all"           then and_product(Array(value).map { |o| branches_of(o, label, errors) })
  when "any"           then Array(value).flat_map { |o| branches_of(o, label, errors) }.uniq
  when "changed-files" then Array(value).flat_map { |m| branches_of(m, label, errors) }.uniq
  when *OR_GLOB_KEYS   then Array(value).map { |g| leaf(g) }.uniq
  when *AND_GLOB_KEYS  then [ Array(value).map { |g| leaf(g) }.reduce(NEUTRAL) { |a, b| merge(a, b) } ]
  when *BRANCH_KEYS    then [ NEUTRAL ]
  else
    # An unrecognised key is not merely odd — the walker cannot look INSIDE it,
    # so a negative glob nested there would pass unseen. Fail instead.
    errors << "#{label}: невідомий ключ матчера #{key.inspect} — walker не бачить його вмісту"
    [ NEUTRAL ]
  end
end

config = YAML.safe_load_file(LABELER)
unless config.is_a?(Hash)
  abort("labeler_config_check: #{LABELER} не Hash верхнього рівня")
end

# ── CHECK A — negative globs must never stand alone in a branch ──────────────
total_branches = 0
total_negatives = 0

config.each do |label, rules|
  branches = Array(rules).flat_map { |o| branches_of(o, label, errors) }.uniq
  total_branches += branches.size
  total_negatives += branches.sum { |b| b[:neg].size }

  branches.select { |b| b[:neg].any? && !b[:pos] }.each do |bad|
    errors << "#{label}: негативний глоб #{bad[:neg].join(', ')} утворює САМОДОСТАТНЮ гілку " \
              "(матчери дефолтяться в `any:`/OR) → лейбл липне на кожен PR поза виключенням. " \
              "Потрібна `all:`-кон'юнкція з позитивним глоб-блоком (00_05 §2.6)"
  end
end

# ── CHECK B — labeler keys ⊆ labels.yml (Labels-as-Code SSOT) ────────────────
declared = Array(YAML.safe_load_file(LABELS_YML)).filter_map { |l| l["name"] if l.is_a?(Hash) }
(config.keys - declared).each do |phantom|
  errors << "#{phantom}: ключ labeler.yml відсутній у .github/labels.yml → " \
            "правило інертне (labeler лейбла не створює), клас `module:06-infra` (00_05 §4)"
end

# ── report ──────────────────────────────────────────────────────────────────
if errors.empty?
  puts "labeler_config_check ✓ — #{config.size} правил, #{total_branches} OR-гілок " \
       "(#{total_negatives} негативних глобів AND-обгорнуто), ключі ⊆ labels.yml (#{declared.size})"
  exit 0
else
  warn "labeler_config_check ✗ — .github/labeler.yml (OPS.3):"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
