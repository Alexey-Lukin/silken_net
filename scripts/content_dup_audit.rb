#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/content_dup_audit.rb — полювання на ОДНАКОВИЙ КОНТЕНТ у різних доках
# (One-Home порушення, яких per-value лінтери не ловлять). Доповнює format-аудит
# (crossref_audit.rb): той дивиться ФОРМУ рефів, цей — змістову дуплікацію.
#
# Метод: нормалізує кожен контент-рядок (prose / table-cell), будує мапу
# normalized → {docs}, і репортує рядки, що дослівно повторюються у ≥2 доках —
# тобто copy-paste, який мав би жити в ОДНОМУ домі + реф (00_06 §2). Read-only.
#
# Usage: ruby scripts/content_dup_audit.rb [--min N] [--all]
#   --min N   мін. к-сть доків (default 2)   --all  показати й within-module пари

MIN  = (i = ARGV.index("--min")) ? ARGV[i + 1].to_i : 2
ALL  = ARGV.delete("--all")
root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort

# normalize a line for dup-comparison; nil = skip (heading/fence/trivial/structural)
def norm(line)
  l = line.strip
  return nil if l.empty?
  return nil if l.start_with?("#", "```", "<!--", "|--", "> ", ">")        # heading/fence/quote/sep
  return nil if l =~ /\A[-*]\s*\[[ x]\]/ || l =~ /\A\|?\s*-{3,}/            # checkbox / hr
  l = l.sub(/\A[-*+]\s+/, "").sub(/\A\d+\.\s+/, "")                        # list markers
  l = l.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')                               # links → label
  l = l.gsub(/[`*_~]/, "").gsub(/§\s*[\w.\-]+/, "").gsub(/\s+/, " ").strip # md + §-tokens
  l = l.downcase
  words = l.scan(/[\p{L}\p{N}]+/)
  return nil if words.size < 8 || l.length < 50                           # too short to be telling
  return nil if l.count("0-9") > l.length / 2                             # mostly numbers (BOM-like)
  l
end

seen = Hash.new { |h, k| h[k] = [] }   # normalized → [ [doc, raw], ... ]
files.each do |path|
  base = File.basename(path)[0, 5]
  in_fence = false
  File.foreach(path) do |line|
    in_fence = !in_fence if line.start_with?("```")
    next if in_fence
    n = norm(line)
    next unless n
    seen[n] << [ base, line.strip ] unless seen[n].any? { |d, _| d == base }
  end
end

dups = seen.select { |_, v| v.map(&:first).uniq.size >= MIN }
            .sort_by { |_, v| -v.size }

puts "═══ Content duplication — рядки, що повторюються у ≥#{MIN} доках ═══\n\n"
shown = 0
dups.each do |_n, occ|
  docs = occ.map(&:first).uniq
  mods = docs.map { |d| d[0, 2] }.uniq
  next if !ALL && mods.size < 2 && docs.size < 3   # within-one-module → likely legit unless 3+
  shown += 1
  puts "▸ #{docs.size} доків [#{docs.join(', ')}]"
  puts "    «#{occ.first.last[0, 140]}»"
  puts
end
puts "── #{shown} кандидатів на дуплікацію (з #{dups.size} повторюваних рядків усього)."
puts "   Кожен = той самий зміст у кількох доках → перевір: чи це One-Home факт (→ дім + реф), чи легітимний спільний контекст."
