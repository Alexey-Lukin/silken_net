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
# Usage: ruby scripts/content_dup_audit.rb [--min N] [--all] [--near [--threshold T]]
#   --min N       мін. к-сть доків (default 2)   --all  показати й within-module пари
#   --near        режим near-dup: той самий факт ІНШИМИ словами (token-set Jaccard,
#                 cross-doc) — ловить reworded One-Home порушення, яких exact-режим
#                 і per-value лінтери не бачать. On-demand (шумний за природою; НЕ CI-гейт).
#   --threshold T поріг подібності для --near (default 0.82)

MIN  = (i = ARGV.index("--min")) ? ARGV[i + 1].to_i : 2
ALL  = ARGV.delete("--all")
NEAR = ARGV.delete("--near")
THRESHOLD = (i = ARGV.index("--threshold")) ? ARGV[i + 1].to_f : 0.82
root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort

# normalize a line for dup-comparison; nil = skip (heading/fence/trivial/structural)
def norm(line)
  l = line.strip
  return nil if l.empty?
  return nil if l.start_with?("#", "```", "<!--", "|--", "> ", ">")        # heading/fence/quote/sep
  return nil if l =~ /\A[-*]\s*\[[ x]\]/ || l =~ /\A\|?\s*-{3,}/            # checkbox / hr
  # skip navigation that repeats across docs BY DESIGN (not One-Home content drift):
  #   · cross-ref directory rows — table row whose first cell is a doc-link `[…](NN_NN_…)`
  #     (Cross-references / home-registry tables; every doc links the same siblings)
  #   · per-doc `Поточний TRL` Статус lines (each doc declares its own member-TRL — skeleton-required)
  return nil if l =~ /Поточний TRL/
  return nil if l.start_with?("|") && l.split("|")[1].to_s =~ /\]\(\d\d_\d\d_/
  l = l.sub(/\A[-*+]\s+/, "").sub(/\A\d+\.\s+/, "")                        # list markers
  l = l.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')                               # links → label
  l = l.gsub(/[`*_~]/, "").gsub(/§\s*[\w.\-]+/, "").gsub(/\s+/, " ").strip # md + §-tokens
  l = l.downcase
  words = l.scan(/[\p{L}\p{N}]+/)
  return nil if words.size < 8 || l.length < 50                           # too short to be telling
  return nil if l.count("0-9") > l.length / 2                             # mostly numbers (BOM-like)
  l
end

if NEAR
  # --- near-duplicate mode: token-set Jaccard across DIFFERENT docs ---
  # Catches REWORDED One-Home violations (same fact, other words) that the exact-line
  # mode and per-value linters miss — the manual semantic audit (00_06 §3) made
  # assistive. Inverted index on rare words (len≥7) prunes the O(n²) pair space.
  entries = []   # [doc, raw, uniq-words]
  files.each do |path|
    base = File.basename(path)[0, 5]
    in_fence = false
    File.foreach(path) do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      n = norm(line) or next
      ws = n.scan(/[\p{L}\p{N}]+/).select { |w| w.length >= 4 }.uniq
      entries << [ base, line.strip, ws ] if ws.size >= 6
    end
  end
  idx = Hash.new { |h, k| h[k] = [] }
  entries.each_with_index { |(_, _, ws), i| ws.each { |w| idx[w] << i if w.length >= 7 } }
  seen_pairs = {}
  hits = []
  idx.each_value do |bucket|
    bucket.combination(2).each do |i, j|
      next if seen_pairs[[ i, j ]]
      seen_pairs[[ i, j ]] = true
      next if entries[i][0] == entries[j][0]                 # cross-doc only
      wi, wj = entries[i][2], entries[j][2]
      jac = (wi & wj).size.to_f / (wi | wj).size
      hits << [ jac, i, j ] if jac >= THRESHOLD && jac < 1.0  # 1.0 = literal → exact mode
    end
  end
  hits.sort_by! { |jac, _, _| -jac }
  puts "═══ Near-duplicate (Jaccard ≥ #{THRESHOLD}, cross-doc) — той самий факт іншими словами ═══\n\n"
  hits.first(40).each do |jac, i, j|
    puts "▸ #{(jac * 100).round}%  [#{entries[i][0]} ↔ #{entries[j][0]}]"
    puts "    #{entries[i][0]}: «#{entries[i][1][0, 120]}»"
    puts "    #{entries[j][0]}: «#{entries[j][1][0, 120]}»"
    puts
  end
  puts "── #{hits.size} near-dup пар (показано #{[ hits.size, 40 ].min}). Кожна → One-Home: дім + реф, чи легітимний контекст?"
  exit
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
