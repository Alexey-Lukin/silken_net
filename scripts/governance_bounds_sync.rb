#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Governance-bounds sync gate (GOV.3) — sibling of governance_key_sync (GOV.2).
#
# GOV.2 pins the NAMES of the ProtocolParameters.sol ⟷ ParameterSyncWorker
# bridge (keccak-string set equality). This gate pins the VALUES on the OTHER
# mirror of the same worker: the `min`/`max`/value_type/category that
# `PARAMETER_MAP` writes into every governance-synced SystemParameter MUST match
# the `db/seeds.rb` default for that key. Canon (05_06 §7) already declares the
# invariant in prose — "One-Home меж = PARAMETER_MAP ↔ db/seeds.rb" — but nothing
# enforced the `↔`.
#
# Two homes, deliberately NOT collapsed (like the keccak bridge): seeds carries
# every bootstrap default with values + descriptions (dev/test); PARAMETER_MAP
# carries the sync-config of the governance-synced economic SUBSET. For that
# subset the bounds/type/category must be identical — the worker comment says so
# verbatim ("той самий запис, та сама валідація"). Neither side is tallied here
# on purpose: both sets legitimately grow and shrink with the protocol, and the
# script PRINTS the live economic count on success — a number frozen in this
# header would just rot (it did: it read "26 seeds / 17 local" against a file
# holding 22 / 13). Three silent-failure classes this closes:
#
#   1. a bounds drift — seeds floor edited but not PARAMETER_MAP (or vice-versa):
#      the E.64 class, review-caught 2026-07-11 (stress_threshold min 0.5 in
#      seeds vs 0.65 in the map) — a governance vote could then land a value the
#      OTHER mirror would have rejected, and the dev default disagrees with prod;
#   2. a value_type/category drift — the worker converts on-chain fixed-point BY
#      value_type (integer truncates, float/decimal keep fraction) and writes the
#      category; a "float"-in-map vs "integer"-in-seeds mismatch silently
#      mis-scales the synced value;
#   3. a PARAMETER_MAP key with NO seed default — the DAO can vote it on-chain,
#      but until the first sync `SystemParameter.current` is nil → the code
#      falls back to its hardcoded default, so the seed IS the precondition for
#      the governed value to exist at all. (The reverse — a seed key absent from
#      PARAMETER_MAP — is by design: the LOCAL/inert keys are deliberately not
#      synced, per the seeds comments, so the check is directional.)
#
# Pure Ruby (stdlib only — the worker pulls in `eth` + ApplicationWeb3Worker, and
# seeds.rb runs AR `.create!`, so BOTH sides are regex-scanned, not required). A
# pattern that stops matching aborts as a dead-mirror tripwire rather than
# passing vacuously. Run:
#   ruby scripts/governance_bounds_sync.rb
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.

ROOT   = File.expand_path("..", __dir__)
SEEDS  = File.join(ROOT, "db/seeds.rb")
WORKER = File.join(ROOT, "app/workers/governance/parameter_sync_worker.rb")

errors = []

# ── numeric literals in both files use Ruby underscores (10_000) and mixed
#    forms (0.10 / 1000.0 / 0) — normalise to Float for value equality. Both
#    sides are the SAME written decimal literal, so Float() is bit-identical
#    (no arithmetic, just parsing) — 0.10 == 0.1, 100_000 == 100000. ──────────
def num(literal)
  Float(literal.delete("_"))
end

# ── seeds: the `system_params = [ {…}, {…} ]` array of default records ────────
seeds = File.read(SEEDS)
seeds_block = seeds[/system_params\s*=\s*\[(.*?)^\]/m, 1] or
  abort("governance_bounds_sync: `system_params = [ … ]` не розпарсився у db/seeds.rb (форма змінилась?)")

# Each entry is a single `{ … }` hash (descriptions never contain braces, so a
# brace-free capture isolates one record); pull the named fields by key so a
# number inside a description ("2%", "0.6") can never be mistaken for a bound.
seed_rows = {}
seeds_block.scan(/\{([^{}]+)\}/) do |(inner)|
  key = inner[/key:\s*"([^"]+)"/, 1] or next
  seed_rows[key.to_sym] = {
    value_type: inner[/value_type:\s*"([^"]+)"/, 1],
    category:   inner[/category:\s*"([^"]+)"/, 1],
    min:        inner[/min_value:\s*([0-9_.eE+-]+)/, 1],
    max:        inner[/max_value:\s*([0-9_.eE+-]+)/, 1]
  }
end
abort("governance_bounds_sync: жодного seed-запису не витягнуто з system_params (форма змінилась?)") if seed_rows.empty?

# ── worker: PARAMETER_MAP (the governance-synced economic keys) ──────────────
worker = File.read(WORKER)
param_block = worker[/PARAMETER_MAP\s*=\s*\{(.*?)^\s*\}\.freeze/m, 1] or
  abort("governance_bounds_sync: PARAMETER_MAP не розпарсився у parameter_sync_worker.rb (форма змінилась?)")

param_rows = {}
param_block.scan(/^\s*(\w+):\s*\{([^}]*)\}/) do |key, inner|
  param_rows[key.to_sym] = {
    value_type: inner[/value_type:\s*"([^"]+)"/, 1],
    category:   inner[/category:\s*"([^"]+)"/, 1],
    min:        inner[/min:\s*([0-9_.eE+-]+)/, 1],
    max:        inner[/max:\s*([0-9_.eE+-]+)/, 1]
  }
end
abort("governance_bounds_sync: жодного ключа не витягнуто з PARAMETER_MAP (форма змінилась?)") if param_rows.empty?

# ── compare: every synced key must have a seed default with identical config ──
param_rows.each do |key, pm|
  seed = seed_rows[key]
  unless seed
    errors << "`#{key}` є в PARAMETER_MAP, але НЕ сідирується у db/seeds.rb — " \
              "DAO проголосує його on-chain, а до першого sync `SystemParameter.current` = nil " \
              "→ код падає на хардкод-дефолт (seed = передумова керованого значення)"
    next
  end

  %i[value_type category].each do |field|
    next if seed[field] == pm[field]
    errors << "`#{key}` #{field}: db/seeds.rb=#{seed[field].inspect} ≠ PARAMETER_MAP=#{pm[field].inspect} " \
              "— worker конвертує/пише за цим полем (mis-scale / хибна категорія)"
  end

  %i[min max].each do |field|
    if seed[field].nil? || pm[field].nil?
      errors << "`#{key}` #{field}: db/seeds.rb=#{seed[field].inspect} PARAMETER_MAP=#{pm[field].inspect} — межа відсутня з одного боку"
    elsif num(seed[field]) != num(pm[field])
      errors << "`#{key}` #{field}: db/seeds.rb=#{seed[field]} ≠ PARAMETER_MAP=#{pm[field]} " \
                "— bounds-drift (клас E.64: одне дзеркало правлене, друге ні)"
    end
  end
end

# ── report ────────────────────────────────────────────────────────────────────
if errors.empty?
  puts "governance_bounds_sync ✓ — db/seeds.rb ⟷ PARAMETER_MAP " \
       "(#{param_rows.size} економічних ключів: bounds/value_type/category узгоджені; 05_06 §7 One-Home меж)"
  exit 0
else
  warn "governance_bounds_sync ✗ — seed↔PARAMETER_MAP bounds drift (GOV.3):"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
