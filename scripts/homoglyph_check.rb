#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🔤 HOMOGLYPH CHECK — a word that MIXES alphabets is invisible to every grep
# =============================================================================
# A bilingual corpus typed with a layout switch produces words that LOOK correct
# and are not: `бланкет` with a Latin `a`, `зашироко` with a Latin `o`. Nothing
# renders differently, no spell-checker runs here, and the cost is exact — the
# word stops answering to its own name. Someone grepping `бланкет` gets zero
# hits; the i18n glossary carried `броадкаст` with a Latin `o`, i.e. a GLOSSARY
# entry unreachable by lookup, which is the one thing a glossary is for.
#
# 🔴 It also SPREADS: `зашироко` was found in two files, one copied from the
# other, so a single mistyped character propagates by quotation.
#
# MEASURED BEFORE BUILDING (00_05 §5 — enumerate every candidate first):
#   · Latin-inside-Cyrillic: 8 hits, 7 distinct words, **8 of 8 genuine** —
#     100% precision. The legitimate hybrids this corpus writes on purpose
#     (`callerів`, `guardами`, `legalізовано`, `specмапу`) are excluded by
#     construction, because their Latin part is a whole English STEM, not one
#     or two look-alike characters.
#   · Cyrillic-inside-Latin: **0 hits** across docs, skills, app, lib, config,
#     spec, contracts, subgraph, workflows, terraform and firmware. The
#     extension is therefore free (measure the perimeter's price BEFORE
#     switching it on), and it guards the more expensive direction: a Cyrillic
#     look-alike inside an ENV name or a hostname is a live defect, not prose.
#
# 🔒 DECLARED CEILINGS — what this gate does NOT judge:
#   · a word written ENTIRELY in the wrong alphabet — `config` with ONE Cyrillic
#     look-alike is caught, `конфіг` spelled out in Cyrillic is not, because that
#     is a translation choice rather than a corruption;
#   · homoglyphs outside the Latin/Cyrillic pair (Greek ο, fullwidth forms);
#   · anything inside a fenced code block — deliberately NOT excluded, because
#     the mirror direction is at its most dangerous exactly there;
#   · a REGEX ESCAPE glued to Cyrillic (`\AМета`, `\AПольові`) — measured as the
#     ONLY false-positive family when the perimeter widened past docs, 3 of 7
#     hits, and it is excluded structurally rather than by an allowlist: the
#     stray Latin letter there is preceded by a backslash, which no mistyped
#     character ever is. ⚠️ The docs-only measurement said 100% precision; the
#     widened one said 57% until this exclusion landed — a precision figure is a
#     statement about a PERIMETER, never about a detector.
#
# ⚠️ This header names its examples instead of embedding them: an illustrative
# corrupt literal would make the gate fail on its own documentation, and the
# honest fix is to describe (a Cyrillic `о` inside the word `config`) rather
# than to teach the gate not to look at itself.
# =============================================================================

require "set"

# Latin characters that have a Cyrillic look-alike, → the Cyrillic they were meant to be.
LATIN_TO_CYRILLIC = {
  "a" => "а", "c" => "с", "e" => "е", "i" => "і", "o" => "о", "p" => "р",
  "x" => "х", "y" => "у", "A" => "А", "B" => "В", "C" => "С", "E" => "Е",
  "H" => "Н", "K" => "К", "M" => "М", "O" => "О", "P" => "Р", "T" => "Т",
  "X" => "Х", "Y" => "У"
}.freeze

CYRILLIC_TO_LATIN = {
  "а" => "a", "с" => "c", "е" => "e", "і" => "i", "о" => "o", "р" => "p",
  "х" => "x", "у" => "y", "А" => "A", "В" => "B", "С" => "C", "Е" => "E",
  "Н" => "H", "К" => "K", "М" => "M", "О" => "O", "Р" => "P", "Т" => "T",
  "Х" => "X", "У" => "Y"
}.freeze

CYRILLIC = /[А-Яа-яІіЇїЄєҐґЁё]/
LATIN    = /[A-Za-z]/
WORD     = /[A-Za-zА-Яа-яІіЇїЄєҐґЁё]{3,}/

GLOBS = %w[
  docs/**/*.md .claude/**/*.md CLAUDE.md AGENTS.md README.md
  app/**/*.rb lib/**/*.rb config/**/*.rb config/**/*.yml spec/**/*.rb scripts/*.rb
  contracts/**/*.sol subgraph/src/**/*.ts .github/workflows/*.yml terraform/*.tf
  firmware/soldier/**/*.{c,h} firmware/queen/**/*.{c,h} firmware/common/**/*.h
  firmware/bio_contracts/**/*.rb
].freeze

EXCLUDE = %r{/(node_modules|extern|vendor)/}

# A word is CORRUPT when it is overwhelmingly one alphabet and carries one or two
# look-alikes from the other. Both minorities must be homoglyphs — a whole foreign
# stem (`callerів`) is a deliberate hybrid this corpus writes on purpose.
def diagnose(word)
  cyr = word.chars.count { |c| c.match?(CYRILLIC) }
  lat = word.chars.count { |c| c.match?(LATIN) }
  return nil if cyr.zero? || lat.zero?

  if lat <= 2 && cyr >= 3
    strays = word.chars.select { |c| c.match?(LATIN) }
    return nil unless strays.all? { |c| LATIN_TO_CYRILLIC.key?(c) }
    [ :latin_in_cyrillic, word.chars.map { |c| LATIN_TO_CYRILLIC.fetch(c, c) }.join, strays.uniq ]
  elsif cyr <= 2 && lat >= 3
    strays = word.chars.select { |c| c.match?(CYRILLIC) }
    return nil unless strays.all? { |c| CYRILLIC_TO_LATIN.key?(c) }
    [ :cyrillic_in_latin, word.chars.map { |c| CYRILLIC_TO_LATIN.fetch(c, c) }.join, strays.uniq ]
  end
end

findings = []
Dir[*GLOBS].uniq.each do |path|
  next unless File.file?(path)
  next if path.match?(EXCLUDE)

  File.foreach(path).with_index(1) do |raw, lineno|
    # Blank out regex escapes so `\A` cannot glue itself onto the Cyrillic word that
    # follows it. Spaces, not deletion — deletion would fuse the two neighbours instead.
    line = raw.gsub(/\\[A-Za-z]/, "  ")
    line.scan(WORD) do |word|
      kind, suggestion, strays = diagnose(word)
      next unless kind
      findings << { path: path, line: lineno, word: word, suggestion: suggestion, kind: kind, strays: strays }
    end
  end
end

if findings.empty?
  puts "homoglyph_check ✓ — no mixed-alphabet words (#{Dir[*GLOBS].uniq.count { |f| File.file?(f) && !f.match?(EXCLUDE) }} files)"
  exit 0
end

puts "homoglyph_check ✗ — #{findings.size} mixed-alphabet word(s); each is invisible to a grep for its real spelling:"
findings.each do |f|
  arrow = f[:kind] == :latin_in_cyrillic ? "Latin→Cyrillic" : "Cyrillic→Latin"
  puts "  #{f[:path]}:#{f[:line]}  #{f[:word]}  →  #{f[:suggestion]}   (#{arrow}: #{f[:strays].join(', ')})"
end
exit 1
