#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/doc_structure_map.rb — структурна мапа канону SilkenNet.
#
# Для кожної сторінки `docs/NN_NN_*.md` витягує "голову" (title + 🎯 Мета +
# ✅ Статус/TRL + 🔗 cross-refs count + 📏 line-count) і список контент-секцій
# (## ...) — тобто все до кінця змісту-ToC, БЕЗ тіла. Дає компактну мапу всього
# проєкту, щоб орієнтуватися не перечитуючи кожен файл. Per-module heft-підсумок
# (стор · рядків) — для size-rebalance лінзи (small→merge / large→split).
#
# Read-only. Нічого не змінює.
#
# Usage:
#   ruby scripts/doc_structure_map.rb              # увесь канон (00_00..08_99)
#   ruby scripts/doc_structure_map.rb 00_01 00_02  # діапазон [from..to] включно
#   ruby scripts/doc_structure_map.rb --secs       # + повний список § кожної сторінки

SHOW_SECS = ARGV.delete("--secs")
FROM = ARGV[0] || "00_00"
TO   = ARGV[1] || "08_99"

# Front-matter (skeleton) заголовки розпізнаються за МІТКОЮ після емодзі — НЕ за голим
# емодзі. Нумерований контент-заголовок ("## 🎯 5. …", "## 🔗 7. …") має той самий емодзі,
# але це РЕАЛЬНА секція й не має фільтруватись (це був тихий баг — ховав 7 секцій канону).
SKELETON_LABELS = /\A(Мета|Статус|Cross-references?|Зміст|TOC|File\s*Map|Файлова)/i

def skeleton_kind(heading)
  core = heading.sub(/\A[^\p{L}\p{N}]+/u, "") # зняти провідні емодзі + пробіли
  return nil unless core =~ SKELETON_LABELS

  core =~ /\AМета/i ? :meta : (core =~ /\AСтатус/i ? :status : :other_skel)
end

root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort
files.select! { |f| key = File.basename(f)[0, 5]; key >= FROM && key <= TO }

abort "Жодного docs/NN_NN файлу в діапазоні #{FROM}..#{TO}" if files.empty?

prev_mod = nil
total_secs = 0
total_lines = 0
mod_pages = Hash.new(0)
mod_lines = Hash.new(0)

files.each do |path|
  base   = File.basename(path)
  key    = base[0, 5]
  mod    = base[0, 2]
  lines  = File.readlines(path, chomp: true)

  h1 = (lines.find { |l| l.start_with?("# ") } || "# (no H1)").sub(/^#\s+/, "")

  meta = status = nil
  crossrefs = 0
  content_secs = []
  cur_skel = nil  # :meta / :status / :other_skel для поточної ## секції; nil = контент
  in_fence = false

  lines.each do |l|
    in_fence = !in_fence if l.start_with?("```")
    next if in_fence  # skip ## inside ``` fences (skeleton/template examples ≠ real sections)

    if l.start_with?("## ")
      heading  = l.sub(/^##\s+/, "").strip
      cur_skel = skeleton_kind(heading)        # за міткою, не за голим емодзі
      content_secs << heading unless cur_skel  # нумерована "🎯 5. …" — це контент
    elsif cur_skel
      next if l.strip.empty?
      if cur_skel == :meta && meta.nil? && !l.start_with?("#")
        meta = l.strip.delete_prefix("> ")
      elsif cur_skel == :status && status.nil? && l =~ /TRL/i
        status = l.strip.delete_prefix("> ")
      end
    end
    crossrefs += l.scan(/\[`?\d\d_\d\d/).size if l.include?("](")
  end
  # Жодного фолбеку: док без `✅ Статус` (00_00 index · 00_07 tracker — skeleton-винятки)
  # не має TRL за конструкцією, і вгадувати його першим-ліпшим рядком «TRL N» означає
  # показувати СУСІДНЮ властивість під іменем Статусу. Улов старого щабля був рівно один
  # і хибний: 00_07 малювався з «TRL 4→6» із тіла пункту HW.1.
  total_secs += content_secs.size
  total_lines += lines.size
  mod_pages[mod] += 1
  mod_lines[mod] += lines.size

  if mod != prev_mod
    tier = case mod
    when "00" then "Фундамент (read-first)"
    when "01", "02", "03", "04", "05", "06" then "Tier I — інженерний канон"
    # Структура двошарова з 2026-08-22 (DOC-T.83): Tier II розчинено, модулів 07+ немає.
    # Гілка лишається як ДЕТЕКТОР, не як мітка: док поза 00–06 означає, що хтось завів
    # новий модуль, не оновивши цю карту — і мапа мусить це КРИЧАТИ, а не вигадувати ярус.
    else "⚠️ ПОЗА оголошеною двошаровою структурою — оновіть карту"
    end
    puts "\n══════════ Модуль #{mod} · #{tier} ══════════"
    prev_mod = mod
  end

  puts "\n▸ #{key} — #{h1}"
  puts "  🎯 #{meta}"              if meta
  puts "  ✅ #{status}"            if status
  puts "  🔗 ~#{crossrefs} doc-links"
  puts "  📏 #{lines.size} рядків"
  puts "  §  #{content_secs.size} секцій: " + content_secs.join(" · ") if SHOW_SECS && !content_secs.empty?
  puts "  §  #{content_secs.size} секцій"                              if !SHOW_SECS && !content_secs.empty?
end

puts "\n──────────"
puts "Heft по модулях (стор · рядків) — лінза size-rebalance (small→merge / large→split):"
mod_pages.keys.sort.each { |m| puts "  M#{m}: #{mod_pages[m]} стор · #{mod_lines[m]} рядків" }
puts "Разом: #{files.size} сторінок, #{total_secs} контент-секцій, #{total_lines} рядків (діапазон #{FROM}..#{TO})."
