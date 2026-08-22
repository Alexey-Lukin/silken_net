#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# [SSOT anti-drift, DOC-T.26] docs/protocols/ canon-ref RESOLUTION gate (HARD, CI docs.yml).
#
# The docs/protocols/ subtree (lab RFQ, in-silico pipeline, anchor IP, outreach) references
# top-level canon by RELATIVE path — `[`NN_NN §X`](../../NN_NN_Name)` — a form the top-level
# doc gates never see: docs:check_refs scans only `docs/*.md` and its regexes expect an
# ABSOLUTE `(NN_NN_Name)` href. So a canon rename/renumber or a section collapse silently
# rots these refs (the §1.3→§5 class, but in protocols/). This gate closes that blind spot.
#
# Scope = RESOLUTION only (DOC-T.26 Option A — protocols/ ref FORM is already clean, 84
# well-formed relative links; we do NOT force form, only that every canon-ref resolves):
#   (1) a relative-href target `../../NN_NN_Name` → the doc must exist;
#   (2) a `NN_NN §X` ref → §X must resolve to a real heading number in the target
#       (reuses the proven boundary/parent-aware Tracker::Dashboard.file_section_dangling_refs);
#   (3) a relative-href `#anchor` fragment → must resolve to a heading slug (DocsGraph.anchor_set);
#   (4) a bare code-span `NN_NN` mention → its NN_NN prefix must match an existing doc.
#
# Intra-subtree filename-links (`[`SUMMARY.md`](SUMMARY.md)`, paper/ drafts) are the subtree's
# OWN convention, not NN_NN canon refs → out of scope by design.
#
# Pure Ruby, no Rails. Run from repo root: `ruby scripts/protocols_ref_check.rb`.
require_relative "../lib/tracker/dashboard"
require_relative "../lib/docs_graph"
require "set"

DOCS = File.expand_path("../docs", __dir__)
top  = Dir[File.join(DOCS, "*.md")]
existing  = top.map { |f| File.basename(f, ".md") }.to_set                 # NN_NN_Full basenames
prefixes  = existing.filter_map { |b| b[/\A\d\d_\d\d/] }.to_set            # NN_NN prefixes
anchors   = top.to_h { |f| [ File.basename(f, ".md"), DocsGraph.anchor_set(File.read(f)) ] }

protocols = Dir[File.join(DOCS, "protocols", "**", "*.md")].sort
violations = []

protocols.each do |f|
  rel  = f.sub("#{DOCS}/", "")
  text = File.read(f)

  # (1)+(3) relative-href canon links: target exists, the `../`-DEPTH actually lands
  # on docs/, optional #anchor resolves. `.md` is optional-but-usual: the protocols/
  # subtree writes the extension, and without this the scan matched 1 link of 142
  # (silent since DOC-T.26 landed).
  # The depth half closes the sibling blind spot: the check was NAME-only, so a wrong
  # `../` count passed while rendering a dead link — `paper/` (4 levels deep) carried
  # `../../../00_02_…`, resolving to docs/protocols/00_02_… i.e. nowhere, and CI stayed
  # green because the BASENAME was a real canon doc (found 2026-07-25, 2 live hits).
  text.scan(%r{\]\(((?:\.\./)+)(\d\d_\d\d_[A-Za-z0-9_]+)(?:\.md)?(#[^)]*)?\)}).each do |ups, base, frag|
    unless existing.include?(base)
      violations << "#{rel}: dangling canon link → `#{base}` (no such doc)"
      next
    end
    landed = File.dirname(File.expand_path("#{ups}#{base}", File.dirname(f)))
    unless landed == DOCS
      violations << "#{rel}: wrong `../`-depth → `#{ups}#{base}` resolves into #{landed.sub(File.dirname(DOCS) + '/', '')}/, not docs/"
    end
    if frag
      slug = frag.delete_prefix("#").downcase
      violations << "#{rel}: stale #anchor → `#{base}#{frag}`" unless anchors[base]&.include?(slug)
    end
  end

  # (2) stale §-refs — reuse the proven boundary/parent-aware resolver (scans `NN_NN §X`
  #     in the text regardless of href form; resolves against top-level headings).
  Tracker::Dashboard.file_section_dangling_refs(text).each { |h| violations << "#{rel}: #{h}" }

  # (4) bare code-span `NN_NN` mention (NOT a link label) → its prefix must be a real doc.
  text.each_line do |line|
    line.scan(/(.|\A)`(\d\d_\d\d)(?:_[A-Za-z0-9_]+|[ §][^`]*)?`/) do |pre, pfx|
      next if pre == "[" # link label, handled by (1)
      violations << "#{rel}: bare canon-ref `#{pfx}` → no doc with that NN_NN" unless prefixes.include?(pfx)
    end
  end
end

if violations.empty?
  puts "protocols_ref_check — #{protocols.size} files scanned; every protocols→canon ref resolves ✓"
else
  puts "protocols_ref_check FAILED (#{violations.size}) — DOC-T.26 (protocols/ canon-ref drift):"
  violations.uniq.sort.each { |v| puts "  ✗ #{v}" }
  exit 1
end
