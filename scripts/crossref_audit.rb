#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/crossref_audit.rb — таксономія форм крос-референсів у каноні SilkenNet.
#
# Сканує docs/NN_NN_*.md і розкладає КОЖНЕ посилання на канон-док за формою
# мітки (label), щоб побачити, скільки різних «діалектів» крос-рефа реально
# вживається — і де є простір для стандартизації (00_06 §1 = ОДИН формат).
#
# Read-only. Buckets:
#   L1  canonical §-link     [`NN_NN §X`](NN_NN_Name)           ← стандарт
#   L2  canonical doc-link   [`NN_NN`](NN_NN_Name)              ← стандарт (whole-doc)
#   LA  + #anchor            [`…`](NN_NN_Name#frag)
#   LD  descriptive-label    [`NN_NN` extra words](NN_NN_Name)  ← контекст усередині мітки
#   LP  plain-text label     [NN_NN …](NN_NN_Name) / escaped    ← без code-span
#   LX  label leads з ІНШИМ id, ніж href (renamed residue — мав би ловити лінтер)
#   CS  bare code-span (поза лінком)  `NN_NN §X`                ← лише exempt-доки
#   AR  00_07 arrow-pointer  → `NN_NN …`                        ← thin-pointer формат
#
# Usage: ruby scripts/crossref_audit.rb [--examples]

SHOW = ARGV.delete("--examples")
root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort

LINK = /\[([^\]]*)\]\((\d\d_\d\d[^)#]*)(#[^)]*)?\)/
DOCID = /\A`?(\d\d_\d\d)/

buckets = Hash.new { |h, k| h[k] = [] }            # tag => [ [doc, sample], ... ]
docs_per = Hash.new { |h, k| h[k] = Hash.new(0) }  # tag => { doc => count }

files.each do |path|
  base = File.basename(path)[0, 5]
  text = File.read(path)
  in_fence = false

  text.each_line do |line|
    in_fence = !in_fence if line.start_with?("```")
    next if in_fence

    # --- markdown links to a canon doc ---
    line.scan(LINK) do |label, href, anchor|
      label = label.strip
      id = href[/\A\d\d_\d\d/]
      lead = label[DOCID, 1]                          # doc-id the label leads with (if any)
      cs   = label.start_with?("`")                   # code-span label?
      tag =
        if anchor
          :LA                                          # any #anchor link
        elsif lead && lead != id
          :LX                                          # label id ≠ href id (renamed residue)
        elsif cs && label =~ /\A`#{id}`\z/
          :L2                                          # [`NN_NN`](Doc)
        elsif cs && label =~ /\A`#{id}\s+§[^`]*`\z/
          :L1                                          # [`NN_NN §X`](Doc)
        elsif cs && label =~ /\A`#{id}_[^`]*`\z/
          :L2f                                         # [`NN_NN_Full_Name`](Doc)
        elsif cs
          :LD                                          # [`NN_NN` +words](Doc) descriptive
        elsif lead && label =~ /\\_/
          :LPe                                         # [NN\_NN\_Full\_Name](Doc) escaped index
        elsif lead
          :LPi                                         # [NN_NN §X](Doc) plain doc-id, no backtick
        else
          :LPp                                         # [prose phrase](Doc) — no doc-id in label
        end
      buckets[tag] << [ base, "[#{label}](#{href}#{anchor})" ]
      docs_per[tag][base] += 1
    end

    # --- 00_07 arrow thin-pointers: `→ \`NN_NN …\`` not in a link ---
    if base == "00_07" && line =~ /→\s*`\d\d_\d\d[^`]*`/
      line.scan(/→\s*(`\d\d_\d\d[^`]*`)/) do |(ref)|
        buckets[:AR] << [ base, ref ]
        docs_per[:AR][base] += 1
      end
    end

    # --- bare code-span refs NOT inside a markdown link ---
    line.gsub(LINK, "").scan(/`\d\d_\d\d[^`]*`/) do |cs|
      buckets[:CS] << [ base, cs ]
      docs_per[:CS][base] += 1
    end
  end
end

LABELS = {
  L1:  "✅ canonical §-link       [`NN_NN §X`](Doc)",
  L2:  "✅ canonical doc-link     [`NN_NN`](Doc)",
  L2f: "🟡 code-span full-name    [`NN_NN_Full_Name`](Doc)",
  LA:  "✅ link + #anchor         [`…`](Doc#frag)",
  LD:  "🟡 descriptive-label      [`NN_NN` +words](Doc)",
  LPe: "🟡 escaped index label    [NN\\_NN\\_Full\\_Name](Doc)",
  LPi: "🔴 plain doc-id label     [NN_NN §X](Doc)  (no code-span)",
  LPp: "✅ prose-phrase label     [текст без doc-id](Doc)",
  LX:  "🔴 label↔href id mismatch (renamed residue)",
  CS:  "⚪ bare code-span         `NN_NN §X`  (exempt-доки)",
  AR:  "⚪ 00_07 arrow-pointer    → `NN_NN …`  (thin-pointer)"
}

puts "═══ Cross-reference taxonomy — #{files.size} canon docs ═══\n\n"
total = buckets.values.sum(&:size)
%i[L1 L2 L2f LA LD LPe LPi LPp LX CS AR].each do |tag|
  rows = buckets[tag]
  next if rows.empty?
  spread = docs_per[tag].sort_by { |_, v| -v }
  puts format("%-3s %-38s %5d  у %d доках", tag, LABELS[tag], rows.size, spread.size)
  top = spread.first(6).map { |d, c| "#{d}:#{c}" }.join(" · ")
  puts "      #{top}"
  if SHOW
    rows.uniq { |_, s| s }.first(3).each { |d, s| puts "        e.g. #{d}  #{s}" }
  end
  puts
end
puts "── Разом крос-рефів: #{total} (L1+L2+LA = канонічні; LD/LP/LX = кандидати на стандартизацію; CS/AR = exempt thin-pointers)"
