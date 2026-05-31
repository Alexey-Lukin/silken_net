#!/usr/bin/env ruby
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
# Safety (00_06 §4 sweep method): dry-run by default (--apply writes); presence-checked
# (unresolved ids REPORTED, left alone); skips ``` fences + spans already in a link.
#
# Usage:
#   ruby scripts/linkify_bare_refs.rb            # dry-run
#   ruby scripts/linkify_bare_refs.rb --apply    # write

APPLY = ARGV.delete("--apply")
root  = File.expand_path("..", __dir__)
docs  = Dir.glob(File.join(root, "docs", "*.md")).sort

MAP = {}            # NN_NN -> full basename (sans .md)
HEADINGS = {}       # full basename -> downcased heading lines (for §-fold validation)
docs.each do |f|
  b = File.basename(f, ".md")
  next unless b =~ /\A\d\d_\d\d_/
  MAP[b[0, 5]] = b
  HEADINGS[b] = File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase
end

EXEMPT = /\A00_00_|\A00_06_|\A00_07_|\A02_06_|_appendix_|\Amanifest/
# code-span (not a link label), optional trailing " §token" on the same line.
SPAN = /(?<!\[)`(docs\/)?(\d\d_\d\d)(_[A-Za-z0-9_]+)?`([ \t]*§[ \t]*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+))?/

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
  [clean, token[clean.length..]]
end

changes  = Hash.new { |h, k| h[k] = [] }
dangling = []
kept_prose = []     # §X left as prose (sub-point/descriptive) — for review

docs.each do |f|
  base = File.basename(f, ".md")
  next if base.match?(EXEMPT)

  in_fence = false
  out = File.readlines(f).map.with_index(1) do |line, ln|
    if line.start_with?("```")
      in_fence = !in_fence
      next line
    end
    next line if in_fence

    line.gsub(SPAN) do
      orig    = Regexp.last_match(0)
      id      = Regexp.last_match(2)
      sect_rw = Regexp.last_match(4)   # full " §X" suffix (or nil)
      token   = Regexp.last_match(5)
      full    = MAP[id]
      unless full
        dangling << "#{base} L#{ln}: #{orig} (no docs/#{id}_*.md)"
        next orig
      end
      clean, tail = token ? split_dots(token) : [nil, ""]
      repl =
        if clean && fold?(full, clean)
          "[`#{id} §#{clean}`](#{full})#{tail}"
        elsif sect_rw
          kept_prose << "#{base} L#{ln}: [`#{id}`](…)#{sect_rw}  (§ not a heading → prose)"
          "[`#{id}`](#{full})#{sect_rw}"
        else
          "[`#{id}`](#{full})"
        end
      changes[base] << [ln, orig, repl]
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
