#!/usr/bin/env ruby
# frozen_string_literal: true

# Phantom tracker-ID gate: code ⟷ 00_07 ID-set.
#
# Code comments (and workflow/config text) cite 00_07 tracker IDs — `[FW.2]`,
# `target ARCH.10`, `→ 00_07 SEC.20` — but nothing validated that the cited ID
# EXISTS: tracker:check resolves refs INSIDE 00_07, and the code trees were a
# blind spot. Proof-case (2026-07-16, found by hand): firmware/queen/main.c
# cited the phantom `ARCH.35-Q2Q` (the real item is ARCH.10) and no gate
# blinked. This is protocols_ref_check's sibling for the ID namespace.
#
# Mechanics: the ID-set = Tracker::Dashboard.all_item_ids (every #### heading
# + table-row first-cell across ALL sections incl. 📌 Backlog / 🗄️ Архів —
# archived IDs stay citable). Prefix families (ARCH, FW, DOC-T, …) are DERIVED
# from that set, so a token like `PM2.5` or `TLS1.2` whose prefix is not a
# tracker family is never considered. A hyphen-tail is kept only while it
# stays UPPERCASE/digits (`ARCH.35-Q2Q` → one token, flagged) — a lowercase
# tail is prose (`FW.2-gated` → `FW.2`, resolves). CHEM.N notes are bullets,
# not items, so the CHEM family is absent here by construction — it has its
# own guard (chem_note_ref_violations).
#
# Pure Ruby, no Rails. Run from repo root: ruby scripts/code_tracker_id_check.rb
# Exit 0 = every cited ID resolves; exit 1 = phantom IDs (lists them).

require_relative "../lib/tracker/dashboard"

ROOT  = File.expand_path("..", __dir__)
TREES = %w[app lib firmware contracts spec scripts tools bin config db].freeze
EXTS  = "{rb,c,h,sol,py,sh,rake,erb,yml,yaml}"

# The tracker parser + its spec fixtures legitimately carry ID-shaped tokens
# that exercise the resolver; CHANGELOG is a frozen event-log (its IDs are
# history, not live refs); this script itself cites the proof-case phantom;
# vendored/build trees are not our prose.
EXEMPT = %r{\A(?:lib/tracker/dashboard\.rb|spec/lib/|CHANGELOG\.md|scripts/code_tracker_id_check\.rb|contracts/(?:out|cache|node_modules|lib)/|firmware/extern/|tools/[^/]+/(?:node_modules|venv)/)}

# ID-shaped tokens that are NOT tracker refs: external standards etc.
KNOWN_BENIGN = %w[E.164].to_set # ITU-T phone-number format

# ID-shaped token: family prefix (may be hyphen-joined like DOC-T) + `.` +
# digit tail; optional UPPERCASE hyphen-segments stay part of the token.
TOKEN_RE = /(?<![A-Za-z0-9_])[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*\.\d[0-9A-Za-z.]*(?:-[A-Z0-9.]+)*/

tracker_md = File.read(Tracker::Dashboard::DEFAULT_PATH)
ids        = Tracker::Dashboard.all_item_ids(tracker_md).to_set
families   = ids.filter_map { |id| id[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*(?=[.\-]\d)/] }.to_set

# A token resolves if it is an item ID, or if 00_07 knows it VERBATIM anywhere
# in its text — facet tags (`FW.20-S2`, `ARCH.41-B`) and sub-IDs (`HW.3.IS`)
# are declared in their item's body, so a facet on the WRONG base (the
# ARCH.35-Q2Q phantom class) still fails: 00_07 never wrote that compound.
def resolves?(tok, ids, tracker_md)
  ids.include?(tok) ||
    tracker_md.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(tok)}(?![0-9A-Za-z])/)
end

files = TREES.flat_map { |t| Dir[File.join(ROOT, t, "**", "*.#{EXTS}")] } +
        Dir[File.join(ROOT, ".github", "**", "*")] +
        Dir[File.join(ROOT, "*.md")]
files = files.select { |p| File.file?(p) }
             .map { |f| f.sub("#{ROOT}/", "") }.uniq.reject { |rel| rel =~ EXEMPT }.sort

phantoms = files.flat_map do |rel|
  text = begin
    File.read(File.join(ROOT, rel))
  rescue ArgumentError
    next [] # non-UTF-8 / binary
  end
  text.each_line.with_index(1).flat_map do |line, n|
    line.scan(TOKEN_RE).flat_map do |tok|
      tok = tok.sub(/[.\-]+\z/, "") # sentence punctuation / dangling hyphen
      # An ID-shaped hyphen segment is a RANGE (`E.20-E.34`) — check each end.
      parts = tok.split(/-(?=[A-Z][A-Za-z0-9]*\.\d)/)
      parts.filter_map do |part|
        next unless families.include?(part[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*/])
        next if KNOWN_BENIGN.include?(part) || resolves?(part, ids, tracker_md)

        "#{rel}:#{n}: `#{part}` не резолвиться в 00_07 (фантом-ID або renamed)"
      end
    end
  end
end.uniq

if phantoms.empty?
  puts "code_tracker_id_check ✓ — #{files.size} files scanned; every cited tracker-ID " \
       "resolves against 00_07 (#{ids.size} IDs, #{families.size} families)"
  exit 0
else
  warn "code_tracker_id_check ✗ — phantom tracker-IDs cited in code (00_07 has no such item):"
  phantoms.sort.each { |p| warn "  · #{p}" }
  exit 1
end
