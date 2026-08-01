#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Robust text search for a BILINGUAL corpus (memory · docs · skills · prompts).
#
# Why this exists instead of `grep`: in this tree a fact is routinely written in
# one language and looked for in the other, wrapped in markdown emphasis, or
# split across a hard-wrapped line — so a plain `grep` returns 0 hits for a fact
# that is demonstrably present. Measured on the live corpus: 8 of 10 "orphaned"
# hooks were FALSE, and a single evening produced four more instances (a hook in
# Cyrillic vs a body in Latin, `пінили **201**` split by bold, a diagnostic
# keyed on `max` instead of the median, and `| tail` eating an exit code).
#
# The failure is systematic, not careless: retrieval succeeds only insofar as
# the retrieval context matches the ENCODING context (Tulving's encoding
# specificity), and a bilingual corpus guarantees the two differ. A rule telling
# the reader to "check both languages" is therefore the wrong FORM — it must be
# remembered at the exact moment attention is elsewhere, and it has already
# failed five times on the person who wrote it. This is the same repair that
# worked for the anti-wall rule: move the carrier into a tool that runs at the
# moment of action.
#
# Normalised on BOTH sides (query and text) before comparing:
#   · markdown emphasis / code spans  **bold** *i* `code` ~~s~~
#   · apostrophe variants  ʼ ’ ‘ ` ´ → '     · dash variants  – — − ‒ → -
#   · non-breaking space, collapsed whitespace
#   · case, Unicode-aware (Cyrillic included, where `grep -i` is unreliable)
#   · line breaks — the file is searched as one stream, so a phrase broken by a
#     hard wrap is still found (two files in this corpus are hard-wrapped)
#
# What it deliberately does NOT do: translate. It cannot know that
# «READ-ONLY = ТИП агента» and "the agent TYPE does" are the same claim. On zero
# hits it falls back to the longest word's STEM and says so — the honest report
# is "this tool found nothing, here is what it tried", never "the fact is absent".
#
# Usage:
#   ruby scripts/mem_find.rb "пінили 201"
#   ruby scripts/mem_find.rb "Lorenz" --docs
#   ruby scripts/mem_find.rb "encoding specificity" --all
#   ruby scripts/mem_find.rb "term" --path tools/ml
module MemFind
  module_function

  REPO = File.expand_path("..", __dir__)
  MEMORY_DIR = File.expand_path(
    "~/.claude/projects/-Users-oleksiilukin-silken-net/memory"
  )

  def trees
    {
      "--memory" => [ MEMORY_DIR ],
      "--docs" => [ File.join(REPO, "docs") ],
      "--skills" => [ File.join(REPO, ".claude") ],
      "--all" => [ MEMORY_DIR, File.join(REPO, "docs"), File.join(REPO, ".claude") ]
    }
  end

  def normalize(str)
    s = str.unicode_normalize(:nfc)
    s = s.gsub(/[*_`~]/, "")
    s = s.tr("ʼ’‘`´", "'")
    s = s.tr("–—−‒", "-")
    s = s.gsub(" ", " ")
    s.gsub(/\s+/, " ").downcase
  end

  # A stem long enough to still discriminate: Slavic inflection lives in the
  # tail, so trimming it is what lets a Ukrainian query survive a case change.
  def stem(word)
    word.length > 6 ? word[0, word.length - 2] : word
  end

  # Returns [path, line_number_or_nil, text]. A nil line means the phrase spans
  # a line break — present in the file, invisible to any line-oriented search.
  def scan(files, needle)
    return [] if needle.to_s.empty?

    files.each_with_object([]) do |path, hits|
      raw = File.read(path, encoding: "UTF-8")
      next unless normalize(raw).include?(needle)

      lines = raw.lines
      matched = lines.each_index.select { |i| normalize(lines[i]).include?(needle) }
      if matched.empty?
        hits << [ path, nil, "(фраза перетинає перенос рядка — є у файлі, не в рядку)" ]
      else
        matched.each { |i| hits << [ path, i + 1, lines[i].strip ] }
      end
    end
  end

  def files_in(roots)
    roots.flat_map { |r| File.directory?(r) ? Dir.glob("#{r}/**/*.md") : [ r ] }.uniq.sort
  end

  def run(argv)
    args = argv.dup
    tree = trees.keys.find { |k| args.delete(k) } || "--memory"
    roots = if (i = args.index("--path"))
              args.delete_at(i)
              [ File.expand_path(args.delete_at(i), REPO) ]
    else
              trees[tree]
    end
    query = args.join(" ")
    if query.strip.empty?
      warn "usage: mem_find.rb <query> [--memory|--docs|--skills|--all|--path DIR]"
      return 2
    end

    files = files_in(roots)
    needle = normalize(query)
    hits = scan(files, needle)
    return report_miss(query, needle, files, roots) if hits.empty?

    puts "#{hits.size} хітів у #{hits.map(&:first).uniq.size} файлах  (нормалізовано: «#{needle}»)"
    hits.group_by(&:first).each do |path, rows|
      puts "\n#{path.sub(MEMORY_DIR, 'memory').sub("#{REPO}/", '')}"
      rows.first(20).each { |_, ln, txt| puts "  #{(ln || '-').to_s.rjust(5)}  #{txt[0, 160]}" }
      puts "  … ще #{rows.size - 20}" if rows.size > 20
    end
    0
  end

  def report_miss(query, needle, files, roots)
    fallback = normalize(stem(query.split(/\s+/).max_by(&:length).to_s))
    alt = fallback.empty? ? [] : scan(files, fallback)
    puts "0 хітів на «#{query}» у #{files.size} файлах (#{roots.map { |r| File.basename(r) }.join(', ')})"
    puts "  нормалізовано до: «#{needle}»"
    if alt.empty?
      puts "  корінь «#{fallback}» — теж 0."
      puts "  ⚠️ Це заява про ІНСТРУМЕНТ, а не про світ: він не перекладає."
      puts "     Якщо факт міг бути записаний іншою мовою — шукай іншомовний відповідник або читай файл."
      return 1
    end
    puts "  ↳ корінь «#{fallback}» дав #{alt.size} у #{alt.map(&:first).uniq.size} файлах:"
    alt.first(12).each { |p, ln, txt| puts "     #{File.basename(p)}:#{ln || '-'}  #{txt[0, 140]}" }
    0
  end
end

exit(MemFind.run(ARGV)) if $PROGRAM_NAME == __FILE__
