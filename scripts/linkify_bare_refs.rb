#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/linkify_bare_refs.rb — convert bare code-span doc refs → canonical links.
#
# Standardizes thread-A bare refs (00_06 §1): a code-span `NN_NN`, `docs/NN_NN`,
# `NN_NN_FullName` or `docs/NN_NN_FullName` becomes the canonical link
# [`NN_NN`](NN_NN_FullName). The label is normalized to the short `NN_NN`; the
# `docs/` prefix and any descriptive _FullName are dropped from the VISIBLE label
# (they live in the href).
#
# Trailing section: when the code-span is immediately followed by ` §X`, the §X is
# FOLDED into the label — `[`NN_NN §X`](Doc)` — but ONLY when §X resolves to a real
# heading in the target (mirrors DocsLinter.section_label_drift, so no advisory drift
# is introduced). A §X that is a sub-point / descriptive word (e.g. §1a.2, §"Фізична",
# §S6.14, §DOC.11) is left as prose AFTER the link (00_06 §1: descriptive context in
# prose, not the §-slot).
#
# Safety (sweep method — `.claude/prompts/module_restructure.md`, крок 3): dry-run by default (--apply writes); presence-checked
# (unresolved ids REPORTED, left alone); skips ``` fences + spans already in a link.
#
# Usage:
#   ruby scripts/linkify_bare_refs.rb                           # dry-run (canon docs/*.md)
#   ruby scripts/linkify_bare_refs.rb --apply                  # write (canon)
#   ruby scripts/linkify_bare_refs.rb 'docs/protocols/**/*.md' # dry-run subdir targets
#   ruby scripts/linkify_bare_refs.rb --apply docs/protocols/anchor/x.md
# Subdir targets get ../-relative hrefs WITH .md (protocols/ convention); canon docs/*.md
# keep the bare wiki-name href. Fences + table rows skipped.

APPLY = ARGV.delete("--apply")
root  = File.expand_path("..", __dir__)
docs_dir = File.join(root, "docs")
corpus = Dir.glob(File.join(docs_dir, "*.md")).sort   # canon NN_NN = the link-TARGET registry
# Files to rewrite: explicit ARGV paths (e.g. docs/protocols/**), else the canon corpus.
targets = (ARGV.empty? ? corpus : ARGV.flat_map { |a| Dir.glob(File.expand_path(a)) }).uniq.sort

MAP = {}            # NN_NN -> full basename (sans .md)
HEADINGS = {}       # full basename -> downcased heading lines (for §-fold validation)
corpus.each do |f|
  b = File.basename(f, ".md")
  next unless b =~ /\A\d\d_\d\d_/
  MAP[b[0, 5]] = b
  HEADINGS[b] = File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase
end

# Href from a target file's dir to a canon doc: docs-root target → bare wiki-name (no .md,
# the canon convention); subdir target (protocols/**) → ../-prefixed REAL path WITH .md
# (matches the existing protocols/ convention, e.g. L1/SUMMARY → ../../../01_03_…md).
def href_for(target_file, docs_dir, full)
  rel = File.dirname(File.expand_path(target_file)).sub(%r{\A#{Regexp.escape(docs_dir)}/?}, "")
  depth = rel.empty? ? 0 : rel.split("/").length
  depth.zero? ? full : ("../" * depth + full + ".md")
end

EXEMPT = /\A00_00_|\A00_06_|\A00_07_|_[Aa]ppendix|\Amanifest/
# code-span (not a link label) `NN_NN`, with an optional § EITHER inside the code-span
# (`NN_NN §X`) OR trailing after it (`NN_NN` §X). g2=NN_NN, g4=inside-§, g5=outside-§.
SPAN = /(?<!\[)`(docs\/)?(\d\d_\d\d)(_[A-Za-z0-9_]+)?(?:[ \t]*§[ \t]*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+))?`(?:[ \t]*§[ \t]*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+))?/

def fold?(full, token)
  return false unless token
  return true  if token.length == 1 && token.match?(/\A\d\z/)      # §1..§9 top-level
  token.length >= 2 && HEADINGS[full]&.include?(token.downcase)    # resolves to a heading
end

# Strip trailing dots (sentence/table punctuation, not part of the section number):
# "5." → ["5", "."], "5.2." → ["5.2", "."], "6.1" → ["6.1", ""]. The tail is
# re-appended OUTSIDE the link so punctuation is preserved, label stays clean.
def split_dots(token)
  clean = token.sub(/\.+\z/, "")
  [ clean, token[clean.length..] ]
end

changes  = Hash.new { |h, k| h[k] = [] }
dangling = []
kept_prose = []     # §X left as prose (sub-point/descriptive) — for review

targets.each do |f|
  base = File.basename(f, ".md")
  next if base.match?(EXEMPT)

  in_fence = false
  out = File.readlines(f).map.with_index(1) do |line, ln|
    if line.start_with?("```")
      in_fence = !in_fence
      next line
    end
    next line if in_fence
    next line if line.lstrip.start_with?("|")   # table row — bare refs exempt (00_06 §3)

    line.gsub(SPAN) do
      orig    = Regexp.last_match(0)
      id      = Regexp.last_match(2)
      token   = Regexp.last_match(4) || Regexp.last_match(5)   # § inside-or-outside the code-span
      full    = MAP[id]
      unless full
        dangling << "#{base} L#{ln}: #{orig} (no docs/#{id}_*.md)"
        next orig
      end
      href = href_for(f, docs_dir, full)
      clean, tail = token ? split_dots(token) : [ nil, "" ]
      repl =
        if clean && fold?(full, clean)
          "[`#{id} §#{clean}`](#{href})#{tail}"
        elsif token
          kept_prose << "#{base} L#{ln}: [`#{id}`](…) §#{token}  (§ not a heading → prose)"
          "[`#{id}`](#{href}) §#{token}"
        else
          "[`#{id}`](#{href})"
        end
      changes[base] << [ ln, orig, repl ]
      repl
    end
  end

  File.write(f, out.join) if APPLY && changes[base].any?
end

total = changes.values.sum(&:size)
folded = changes.values.flatten(1).count { |_, _, r| r.match?(/`\d\d_\d\d §/) }
changes.sort.each do |b, cs|
  puts "\n#{b} (#{cs.size}):"
  cs.each { |ln, o, r| puts "  L#{ln}: #{o}  →  #{r}" }
end
unless kept_prose.empty?
  puts "\n— § kept as prose (sub-point/descriptive, #{kept_prose.size}) —"
  kept_prose.each { |s| puts "  #{s}" }
end
unless dangling.empty?
  puts "\n⚠️ UNRESOLVED bare ids (left untouched, thread-B):"
  dangling.each { |d| puts "  #{d}" }
end
puts "\n#{'=' * 60}"
puts "TOTAL: #{total} conversions (#{folded} with §-fold) across #{changes.size} docs  (#{APPLY ? 'APPLIED ✍️' : 'DRY-RUN'})"
