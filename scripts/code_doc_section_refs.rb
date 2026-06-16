#!/usr/bin/env ruby
# frozen_string_literal: true

#
# [SSOT anti-drift] code→doc §-ref RESOLUTION audit — manual/periodic, REPORT-ONLY (NOT a CI gate).
#
# Code comments reference canon sections by `NN_NN §X` (e.g. "05_05 §3" in a service
# comment). The doc gates (`docs:check_refs`) scan only `docs/**` — they NEVER look at
# code comments. So when a canon section is renumbered or collapsed, code-comment §-refs
# rot SILENTLY. Real case (2026-06-16 deep-audit): slashing policy moved 00_01 §6 → 05_05
# (2026-05-30); the docs were swept, but ~18 `00_01 §6.x` refs in app/ + spec/ comments
# sat stale for weeks — invisible to every gate (the external-doc-path linter only flags
# `docs/NN_NN_Name` PATHS, not bare `§`-refs in comments).
#
# This script reuses the proven boundary/parent-aware resolver
# (`Tracker::Dashboard.file_section_dangling_refs`) over the source trees and reports any
# `NN_NN §X` that no longer resolves to a real heading in its target doc.
#
# 🔴 REPORT-ONLY by intent — deliberately NOT wired into `docs.yml` / `ci.yml`. Code
# comments legitimately carry informal / historical / illustrative refs that a HARD gate
# would false-positive on; a renumber is rare. Run it periodically (like
# `scripts/doc_structure_map.rb`), or right before a canon renumber/section-move, to catch
# the drift class early. Exits 0 always (pure report); promote to a gate only if the
# false-positive rate proves to be zero across the codebase.
#
# Pure Ruby, no Rails. Run from repo root: `ruby scripts/code_doc_section_refs.rb`.
require_relative "../lib/tracker/dashboard"

ROOT  = File.expand_path("..", __dir__)
TREES = %w[app spec lib].freeze

# The §-resolution engine + its unit tests legitimately cite stale-LOOKING example
# refs (fixtures that exercise the resolver) — exempt them, same idea as
# protocols_ref_check skipping the subtree's own filename-link convention.
EXEMPT = %r{\A(?:lib/docs_linter\.rb|lib/docs_graph\.rb|lib/tracker/dashboard\.rb|spec/lib/)}

files = TREES.flat_map { |t| Dir[File.join(ROOT, t, "**", "*.rb")] }
            .map { |f| f.sub("#{ROOT}/", "") }
            .reject { |rel| rel =~ EXEMPT }
            .sort

violations = files.flat_map do |rel|
  Tracker::Dashboard.file_section_dangling_refs(File.read(File.join(ROOT, rel))).map { |h| "#{rel}: #{h}" }
end

if violations.empty?
  puts "code_doc_section_refs — #{files.size} source files scanned; every `NN_NN §X` code-ref resolves ✓"
else
  puts "code_doc_section_refs — #{violations.size} stale code→doc §-refs (report-only, not a CI gate):"
  violations.uniq.sort.each { |v| puts "  ✗ #{v}" }
end
