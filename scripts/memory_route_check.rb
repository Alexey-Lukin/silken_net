#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/memory_route_check.rb — git → памʼять: маршрут, який не бачив НІХТО.
#
# ЩО ЦЕ ЗАКРИВАЄ. Корпус памʼяті живе поза цим репо, але репо на нього
# СПИРАЄТЬСЯ: скіли, плейбуки й `CLAUDE.md` адресують memory-файли по імені
# («деталь → `reference_solidity_audit_stack` memory»). Ці адреси не перевіряв
# жоден гейт: `code_tracker_id_check.rb` сканує `.claude/**` на трекер-ID і
# слагів памʼяті не знає, а `memory_gate.sh` живе по інший бік межі й бачить
# лише струни ВСЕРЕДИНІ корпусу. Тобто напрямок git→памʼять був сліпою зоною
# рівно в той момент, коли він найкрихкіший — під час курації, яка перейменовує
# й зливає файли. Видалення дому мовчки рвало б посилання, а CI лишався зеленим.
#
# ⚠️ Це НЕ дзеркало `memory_gate.sh --audit`. Той тримає цілісність усередині
# корпусу (індекс↔файли, [[струни]]); цей — ЄДИНИЙ, хто дивиться з боку git.
#
# ЧОМУ ПОПЕРЕДЖЕННЯ, А НЕ ПАДІННЯ, для «протухлого роутера». Битий шлях =
# факт (файлу нема) → HARD. «Роутер шле по те, що вже приїхало в git» = судження
# (дублікат може бути законним роутером, якщо несе те, чого приймач не має), і
# гейт, який його червонить, навчав би прибирати ЖИВІ маршрути. Тому друга
# перевірка друкує worklist і не впливає на exit-код.
#
# Usage: ruby scripts/memory_route_check.rb [--verbose]
#   exit 0 = кожна адреса git→памʼять резолвиться · exit 1 = є бита

VERBOSE = ARGV.include?("--verbose")
ROOT    = File.expand_path("..", __dir__)
MEM     = ENV["MEMORY_GATE_DIR"] ||
          File.expand_path("~/.claude/projects/-Users-oleksiilukin-silken-net/memory")

SOURCES = Dir[File.join(ROOT, ".claude/skills/*/SKILL.md")] +
          Dir[File.join(ROOT, ".claude/prompts/*.md")] +
          [ File.join(ROOT, "CLAUDE.md") ]

# Слаг памʼяті: рівно ті чотири родини, які корпус використовує як імена файлів.
# Тримаємо префікси ЯВНО, а не `\w+_\w+` — інакше ловимо кожен ruby-ідентифікатор
# у прикладах коду (той самий клас, що вже коштував нам хибних спрацювань:
# нормалізація, яка зрізає дискримінатор, робить прилад шумним, а не чутливим).
SLUG = /\b((?:reference|feedback|project|log)_[a-z0-9_]+)/

# Каталог, який НЕ є памʼяттю: у `.claude/**` трапляються однойменні речі
# (напр. `project_root`), тож слаг рахуємо лише якщо він схожий на файл корпусу.
def corpus_files = @corpus_files ||= Dir[File.join(MEM, "*.md")].map { File.basename(_1, ".md") }.to_set

require "set"

broken = []
routes = Hash.new { |h, k| h[k] = [] }

SOURCES.each do |path|
  next unless File.file?(path)
  rel = path.sub("#{ROOT}/", "")
  File.readlines(path).each_with_index do |line, i|
    line.scan(SLUG).flatten.uniq.each do |slug|
      # Слаг, якого нема в корпусі І який не схожий на його ім'я, — не адреса.
      # Порогом тут служить сам корпус: якщо файл є — це маршрут; якщо нема, але
      # префікс корпусний — це БИТИЙ маршрут, а не випадковий ідентифікатор.
      if corpus_files.include?(slug)
        routes[slug] << "#{rel}:#{i + 1}"
      else
        broken << { slug:, at: "#{rel}:#{i + 1}" }
      end
    end
  end
end

if broken.any?
  puts "BROKEN git→memory routes (#{broken.size}):"
  broken.each { |b| puts "  #{b[:at]} → #{b[:slug]}.md — no such file in the corpus" }
  puts
  puts "  A skill/prompt/CLAUDE.md sends a reader at a memory file that does not exist."
  puts "  Either the file was renamed/merged during curation (fix the address), or the"
  puts "  slug is a false positive (make the mention not look like an address)."
  exit 1
end

files = SOURCES.count { |p| File.file?(p) }
cites = routes.values.sum(&:size)
puts "OK — #{routes.size} git→memory routes, all resolve (#{cites} citations across #{files} files)"

if VERBOSE
  puts
  routes.sort_by { |s, w| [ -w.size, s ] }.each { |slug, where| puts format("  %-46s %s", slug, where.join(" · ")) }
end
