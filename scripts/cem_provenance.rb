#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Де кожне число в `tools/cad/cem/*.json` взялося — ADVISORY-звіт, НЕ гейт [HW.48].
#
# ⚖️ Ратифіковано founder 2026-09-12 («я за Сковороду: потрібне зробив неважким, а важке — непотрібним»):
# повну вимого-керовану інверсію CEM ВІДХИЛЕНО; береться носій ПІДСТАВИ поруч зі значенням. Цей скрипт —
# перша його половина: він міряє, скільки чисел мають оголошену підставу, і називає ті, що не мають.
#
# 🔴 Чому це не косметика, і ціна виміряна: за один день 2026-09-12 той самий клас коштував тричі —
#   · `L_FREE_UNSUP = 36` розкладала себе в коментарі так, що читалась деривованою, і не була (HW.34);
#   · `gyroid_wall_param` пережив фліп топології, де токен означає інше, і мовчки дав 50 % замість 65 % (HW.33);
#   · `rf_clearance_min_mm = 12` роками дзеркалив ДИЗАЙН-ТОЧКУ як підлогу, і перевірка ловила АДРЕСУ
#     канон-рядка, ніколи його КЛАУЗУ.
# Спільна форма: параметр не носить власної підстави, тож його розходження з нею не має де почервоніти.
#
# Класи (вони і є предметом виміру):
#   requirement — вимога ззовні, яку ми не обирали (CODIT-рана, DIN/ISO-таблиця, підлога вендора)
#   derived     — виведене розрахунком; `from:` мусить назвати, ЧИМ саме
#   design      — дизайн-точка / робочий приклад, що затвердів у число; законно, але мусить бути названо
#   placeholder — ще не рішення; чекає стенду, RFQ або присуду
#   superseded  — присуд зняв цю гілку, застосування не приїхало; число стоїть і не є чинним рішенням
#
# ⛔ Свідомо БЕЗ exit 1 на некласифікованих: гейт над невиміряною множиною або порожній, або постійно
#    червоний, і другий навчає читача скіпати єдиний рядок, що має лишатись гучним (00_05 §5). Гейтом це
#    стане, коли класифікація повна — так стоїть у HW.48.
#
#   ruby scripts/cem_provenance.rb            # звіт
#   ruby scripts/cem_provenance.rb --missing  # лише некласифіковані, по файлах

require "json"

ROOT = File.expand_path("..", __dir__)
CEM_DIR = File.join(ROOT, "tools", "cad", "cem")
PROV_FILE = File.join(CEM_DIR, "_provenance.json")
# ⛔ П'ятий клас доданий 2026-09-12 і він НЕ про походження, а про те, що для читача маніфесту
#    дорожче за походження: значення, чию гілку присуд УЖЕ ЗНЯВ, а застосування не приїхало.
#    Живий взірець — `o_ring_groove_depth_mm` у фланці й радомі: ⚖️ 2026-09-10 поставив ОДИН паз
#    1.344 проти ПЛАСКОЇ кромки, а відвантажена пара зустрічних 0.9 дає стиск −1.1 %, тобто не
#    ущільнює. Без цього класу таке число читається як «design» — тобто як чинне рішення.
CLASSES = %w[requirement derived design placeholder superseded].freeze
SKIP_KEYS = %w[kind name].freeze

def numeric_fields(obj, prefix = "")
  obj.each_with_object({}) do |(k, v), acc|
    next if k.start_with?("_") || SKIP_KEYS.include?(k)

    path = "#{prefix}#{k}"
    case v
    when Hash then acc.merge!(numeric_fields(v, "#{path}."))
    when Numeric then acc[path] = v
    end
  end
end

# Вкладені маніфести (assembly / axial_stack) несуть ЧУЖУ деталь під власним ключем, тож підстава
# живе у kind тієї деталі, не в їхньому. ⛔ Без цього вони читаються «некласифікованими» там, де
# класифіковано рівно те саме число — хибна порожнеча, яка б роздувала борг звіту.
NESTED_KIND = {
  "zone1" => "anchor_zone1",
  "zone2" => "zone2_sleeve",
  "flange" => "cathode_flange",
  "radome" => "radome",
  "capsule" => "anchor_assembly"
}.freeze

def nested_entry(rules, field)
  parts = field.split(".")
  return nil if parts.size < 2

  leaf = parts.last
  owner = parts[0..-2].reverse.find { |seg| NESTED_KIND.key?(seg) }
  return nil unless owner

  rules.dig(NESTED_KIND[owner], leaf)
end

prov = File.exist?(PROV_FILE) ? JSON.parse(File.read(PROV_FILE)) : {}
rules = prov["fields"] || {}

rows = []
Dir.glob(File.join(CEM_DIR, "*.json")).sort.each do |path|
  next if File.basename(path).start_with?("_")

  doc = JSON.parse(File.read(path))
  kind = doc["kind"]
  numeric_fields(doc).each do |field, value|
    entry = rules.dig(kind, field) || rules.dig("*", field) || nested_entry(rules, field)
    rows << { file: File.basename(path), kind: kind, field: field, value: value, entry: entry }
  end
end

missing = rows.reject { |r| r[:entry] }
bad_class = rows.select { |r| r[:entry] && !CLASSES.include?(r[:entry]["class"]) }
derived_no_from = rows.select { |r| r[:entry] && r[:entry]["class"] == "derived" && r[:entry]["from"].to_s.strip.empty? }

if ARGV.include?("--missing")
  missing.group_by { |r| r[:file] }.sort.each do |file, list|
    puts "#{file}:"
    list.sort_by { |r| r[:field] }.each { |r| puts "  #{r[:field]} = #{r[:value]}" }
  end
  exit 0
end

puts "cem_provenance — ADVISORY-звіт [HW.48], не гейт."
puts
puts "⚠️  ВЛАСНА СЛІПОТА, названа першою:"
puts "  · скрипт судить НАЯВНІСТЬ оголошеної підстави, ніколи її ПРАВДИВІСТЬ. `from: «канон 01_01 §5.2»`"
puts "    зеленіє однаково, чи там справді це число, чи інше — рівно та помилка, що коштувала нам"
puts "    `rf_clearance_min_mm` (перевіряли АДРЕСУ, не КЛАУЗУ)."
puts "  · класифікація рукописна, тож «design» і «placeholder» розрізняє людина, а не вимір."
puts "  · поле-дитина успадковує запис від `kind` батька; вкладені маніфести (assembly/axial_stack)"
puts "    тому можуть читатись класифікованими там, де класифіковано ІНШУ деталь."
puts

by_class = rows.group_by { |r| r[:entry] ? r[:entry]["class"] : "НЕ КЛАСИФІКОВАНО" }
puts format("%-20s %s", "клас", "входжень")
puts "-" * 34
(CLASSES + [ "НЕ КЛАСИФІКОВАНО" ]).each do |c|
  n = (by_class[c] || []).size
  puts format("%-20s %5d", c, n) if n.positive?
end
puts "-" * 34
puts format("%-20s %5d  (унікальних імен полів: %d · маніфестів: %d)",
            "УСЬОГО", rows.size, rows.map { |r| r[:field] }.uniq.size,
            rows.map { |r| r[:file] }.uniq.size)

unless derived_no_from.empty?
  puts
  puts "🔴 `derived` БЕЗ `from:` — клас оголошено, підставу ні (#{derived_no_from.size}):"
  derived_no_from.group_by { |r| [ r[:kind], r[:field] ] }.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

unless bad_class.empty?
  puts
  puts "🔴 невідомий клас (#{bad_class.size}) — дозволені: #{CLASSES.join(' · ')}"
  bad_class.group_by { |r| [ r[:kind], r[:field] ] }.keys.sort.each { |k, f| puts "  #{k}.#{f}" }
end

unless missing.empty?
  puts
  names = missing.group_by { |r| [ r[:kind], r[:field] ] }
  puts "НЕ КЛАСИФІКОВАНІ (#{missing.size} входжень у #{names.size} парах kind.field) — `--missing` дає по файлах:"
  names.keys.sort.first(40).each { |k, f| puts "  #{k}.#{f}" }
  puts "  …" if names.size > 40
end
