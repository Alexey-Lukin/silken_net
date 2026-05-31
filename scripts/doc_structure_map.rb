#!/usr/bin/env ruby
# frozen_string_literal: true
#
# scripts/doc_structure_map.rb — структурна мапа канону SilkenNet.
#
# Для кожної сторінки `docs/NN_NN_*.md` витягує "голову" (title + 🎯 Мета +
# ✅ Статус/TRL + 🔗 cross-refs count) і список контент-секцій (## ...) —
# тобто все до кінця змісту-ToC, БЕЗ тіла. Дає компактну мапу всього проєкту,
# щоб орієнтуватися не перечитуючи кожен файл.
#
# Read-only. Нічого не змінює.
#
# Usage:
#   ruby scripts/doc_structure_map.rb              # увесь канон (00_00..08_99)
#   ruby scripts/doc_structure_map.rb 00_01 08_03  # діапазон [from..to] включно
#   ruby scripts/doc_structure_map.rb --secs       # + повний список § кожної сторінки

SHOW_SECS = ARGV.delete("--secs")
FROM = ARGV[0] || "00_00"
TO   = ARGV[1] || "08_99"

SKELETON = /🎯|✅|🔗|📑|Зміст|Cross-ref|Мета|Статус/i

root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort
files.select! { |f| key = File.basename(f)[0, 5]; key >= FROM && key <= TO }

abort "Жодного docs/NN_NN файлу в діапазоні #{FROM}..#{TO}" if files.empty?

prev_mod = nil
total_secs = 0

files.each do |path|
  base   = File.basename(path)
  key    = base[0, 5]
  mod    = base[0, 2]
  lines  = File.readlines(path, chomp: true)

  h1 = (lines.find { |l| l.start_with?("# ") } || "# (no H1)").sub(/^#\s+/, "")

  meta = status = nil
  crossrefs = 0
  content_secs = []
  cur = nil

  lines.each do |l|
    if l.start_with?("## ")
      cur = l.sub(/^##\s+/, "").strip
      content_secs << cur unless cur =~ SKELETON
    elsif cur
      next if l.strip.empty?
      if cur =~ /🎯|Мета/ && meta.nil? && !l.start_with?("#")
        meta = l.strip.delete_prefix("> ")
      elsif cur =~ /✅|Статус/ && status.nil? && l =~ /TRL/i
        status = l.strip.delete_prefix("> ")
      end
    end
    crossrefs += l.scan(/\[`?\d\d_\d\d/).size if l.include?("](")
  end
  status ||= lines.find { |l| l =~ /\bTRL[\s-]?\d/i }&.strip&.slice(0, 90)
  total_secs += content_secs.size

  if mod != prev_mod
    tier = case mod
           when "00" then "Фундамент (read-first)"
           when "01", "02", "03", "04", "05", "06" then "Tier I — інженерний канон"
           else "Tier II — екосистема/стейкхолдери"
           end
    puts "\n══════════ Модуль #{mod} · #{tier} ══════════"
    prev_mod = mod
  end

  puts "\n▸ #{key} — #{h1}"
  puts "  🎯 #{meta}"              if meta
  puts "  ✅ #{status}"            if status
  puts "  🔗 ~#{crossrefs} doc-links"
  puts "  §  #{content_secs.size} секцій: " + content_secs.join(" · ") if SHOW_SECS && !content_secs.empty?
  puts "  §  #{content_secs.size} секцій"                              if !SHOW_SECS && !content_secs.empty?
end

puts "\n──────────"
puts "Разом: #{files.size} сторінок, #{total_secs} контент-секцій (діапазон #{FROM}..#{TO})."
