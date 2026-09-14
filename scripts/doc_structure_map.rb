#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/doc_structure_map.rb — структурна мапа канону SilkenNet.
#
# ТИПОВО — компактна мапа: для кожної сторінки `docs/NN_NN_*.md` один рядок (ключ · TRL · kB · назва),
# назви контент-секцій (## …) і найважчі підсекції (≥ HEAVY_KB) — тобто СКОУП читання, без тіла й без
# голів. Голови доків (🎯 Мета · ✅ Статус · 🔗 · 📏) друкує `--heads`: вони є дзеркалами самих доків,
# і в типовому виводі займали ~85 % байтів мапи, не додаючи нічого до рішення «що відкривати».
# Per-module heft-підсумок (стор · рядків · kB) — для size-rebalance лінзи (small→merge / large→split).
#
# Read-only. Нічого не змінює.
#
# Usage:
#   ruby scripts/doc_structure_map.rb              # компактна мапа всього канону (00_00..08_99)
#   ruby scripts/doc_structure_map.rb 00_01 00_02  # діапазон [from..to] включно
#   ruby scripts/doc_structure_map.rb --heads      # + 🎯 / ✅ / 🔗 / 📏 кожної сторінки (дзеркала голів)
#   ruby scripts/doc_structure_map.rb --secs       # назви секцій повністю, без обрізання

SHOW_HEADS = ARGV.delete("--heads")
SHOW_SECS = ARGV.delete("--secs")
FROM = ARGV[0] || "00_00"
TO   = ARGV[1] || "08_99"
HEAVY_KB = 8   # підсекція важча за це — окремий рядок «важкі», бо саме вона визначає ціну відкриття
SEC_CUT = 34

# Front-matter (skeleton) заголовки розпізнаються за МІТКОЮ після емодзі — НЕ за голим
# емодзі. Нумерований контент-заголовок ("## 🎯 5. …", "## 🔗 7. …") має той самий емодзі,
# але це РЕАЛЬНА секція й не має фільтруватись (це був тихий баг — ховав 7 секцій канону).
SKELETON_LABELS = /\A(Мета|Статус|Cross-references?|Зміст|TOC|File\s*Map|Файлова)/i

def skeleton_kind(heading)
  core = heading.sub(/\A[^\p{L}\p{N}]+/u, "") # зняти провідні емодзі + пробіли
  return nil unless core =~ SKELETON_LABELS

  core =~ /\AМета/i ? :meta : (core =~ /\AСтатус/i ? :status : :other_skel)
end

def bare(heading) = heading.sub(/\A[^\p{L}\p{N}]+/u, "")

def cut(text, max) = text.size > max ? "#{text[0, max - 1].rstrip}…" : text

# 🔴 TRL як ТОКЕН, не як підрядок: `/TRL/` ловив посилання `00_03_TRL_Matrix…` у Статусі сторінок, для яких
# TRL незастосовний, і рядок-носій тоді був про інше. Токен не може стояти всередині ідентифікатора.
TRL_TOKEN = /(?<![_\p{L}\p{N}])TRL(?![_\p{L}])/u

def trl_label(status)
  return nil if status.nil?
  return "TRL —" if status =~ /незастосовн/i

  m = status.match(/TRL\W{0,6}?([0-9](?:\s*[→\-–\/]\s*[0-9])?)/u)
  m ? "TRL #{m[1].gsub(/\s+/, '')}" : "TRL ?"
end

root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort
files.select! { |f| key = File.basename(f)[0, 5]; key >= FROM && key <= TO }

abort "Жодного docs/NN_NN файлу в діапазоні #{FROM}..#{TO}" if files.empty?

prev_mod = nil
total_secs = 0
total_lines = 0
total_bytes = 0
mod_pages = Hash.new(0)
mod_lines = Hash.new(0)
mod_bytes = Hash.new(0)
head_bytes = 0
status_sizes = []

files.each do |path|
  base   = File.basename(path)
  key    = base[0, 5]
  mod    = base[0, 2]
  lines  = File.readlines(path, chomp: true)

  h1 = (lines.find { |l| l.start_with?("# ") } || "# (no H1)").sub(/^#\s+/, "").sub(/\A\d\d_\d\d:\s*/, "")

  meta = status = nil
  status_bytes = 0
  crossrefs = 0
  content_secs = []
  units = [] # [назва, байти] для ## та ### — ціна відкриття підсекції
  cur_skel = nil  # :meta / :status / :other_skel для поточної ## секції; nil = контент
  in_fence = false

  lines.each do |l|
    line_bytes = l.bytesize + 1
    units.last[1] += line_bytes if units.any?
    in_fence = !in_fence if l.start_with?("```")
    next if in_fence  # skip ## inside ``` fences (skeleton/template examples ≠ real sections)

    if l.start_with?("## ")
      heading  = l.sub(/^##\s+/, "").strip
      cur_skel = skeleton_kind(heading)        # за міткою, не за голим емодзі
      content_secs << heading unless cur_skel  # нумерована "🎯 5. …" — це контент
      units << [ bare(heading), line_bytes ] unless cur_skel
    elsif l.start_with?("### ") && cur_skel.nil?
      units << [ "  #{bare(l.sub(/^###\s+/, '').strip)}", line_bytes ]
    elsif cur_skel
      head_bytes += line_bytes if %i[meta status].include?(cur_skel)
      status_bytes += line_bytes if cur_skel == :status
      next if l.strip.empty?
      if cur_skel == :meta && meta.nil? && !l.start_with?("#")
        meta = l.strip.delete_prefix("> ")
      elsif cur_skel == :status && status.nil? && (l =~ TRL_TOKEN || l =~ /незастосовн/i)
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
  total_bytes += File.size(path)
  mod_bytes[mod] += File.size(path)
  mod_pages[mod] += 1
  mod_lines[mod] += lines.size
  status_sizes << [ key, status_bytes ]

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

  # 🔴 БАЙТИ, не рядки: лічильник рядків — доведено поганий проксі ціни відкриття, бо густина
  # розходиться майже на порядок (00_07 ≈ 777 B/рядок, 03_01 ≈ 113 B/рядок при майже однаковому
  # числі рядків). Мапа існує, щоб вирішувати «відкривати чи ні», тож у компактному рядку — kB.
  kb = format("%.0f kB", File.size(path) / 1024.0)
  puts "▸ #{[ key, trl_label(status), kb ].compact.join(' · ')} — #{h1}"
  unless content_secs.empty?
    names = content_secs.map { |s| SHOW_SECS ? bare(s) : cut(bare(s), SEC_CUT) }
    puts "  § #{names.join(' · ')}"
  end
  heavy = units.select { |_, b| b >= HEAVY_KB * 1024 }.sort_by { |_, b| -b }.first(3)
  unless heavy.empty?
    puts "  ⚖ важкі: " + heavy.map { |n, b| format("%s %.0f kB", cut(n.strip, 28), b / 1024.0) }.join(" · ")
  end
  next unless SHOW_HEADS

  puts "  🎯 #{meta}"              if meta
  puts "  ✅ #{status}"            if status
  puts "  🔗 ~#{crossrefs} doc-links"
  puts format("  📏 %d рядків · %.0f kB", lines.size, File.size(path) / 1024.0)
end

puts "\n──────────"
# Свідок голів лишається й у компактному режимі: роздутий ✅ Статус — хвороба, яку старий типовий
# вивід показував випадково (кожна голова друкувалась), а норма `00_06 §1` велить тримати Статус lean.
top = status_sizes.sort_by { |_, b| -b }.first(3).map { |k, b| format("%s %.1f kB", k, b / 1024.0) }
puts format("Голови доків (🎯 Мета + ✅ Статус) разом: %.1f kB — найважчі ✅: %s · повністю: --heads",
            head_bytes / 1024.0, top.join(" · "))
puts "Heft по модулях (стор · рядків) — лінза size-rebalance (small→merge / large→split):"
mod_pages.keys.sort.each { |m| puts format("  M%s: %d стор · %d рядків · %.0f kB", m, mod_pages[m], mod_lines[m], mod_bytes[m] / 1024.0) }
puts format("Разом: %d сторінок, %d контент-секцій, %d рядків, %.1f MB (діапазон %s..%s).", files.size, total_secs, total_lines, total_bytes / 1_048_576.0, FROM, TO)
