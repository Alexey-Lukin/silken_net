#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Прилад рівня скілів — on-demand лінза, НЕ гейт [DOC-T.123].
#
# ЧОМУ закомічений, а не лишився рецептом у памʼяті: вимір 2026-10-17 двічі збрехав
# через сам прилад — регекс імені скіла без цифр не бачив `web3-pipeline` і дав
# «грошовий скіл не прийшов у жодній сесії» (правда — у двох із трьох), а форма
# `cat .claude/skills/{a,b}/SKILL.md` ховала читання. Рецепт прозою зробив би ці
# пастки спадковими (`00_05 §5`); тут вони виправлені в коді. Норма, яку прилад
# міряє, — анатомія скіла за миттю в `00_05 §2`.
#
# Режими — ростер у `case` унизу; кожен друкує ВЛАСНУ сліпоту перед результатом:
#   --listing        по кожному SKILL.md: `description`+`when_to_use` проти стелі списку ·
#                    тіло в символах і частка за зрізом компакції · де закінчується кожен
#                    генерований індекс і де вперше названо кожен компаньйон.
#   --trigger        по головних транскриптах: чи скіл завантажено ДО першої правки файлу
#                    його домену — окремо для правок до і після першої компакції сесії.
#   --reorder FILE HEADING…   переставити `## `-розділи SKILL.md у названому порядку (решта —
#                    слідом, у своєму порядку) з доказом нульової втрати рядків.
#
# 🔴 Стелі:
#   · стеля списку й точка зрізу — виміряні константи харнесу (документація: «1,536
#     characters», «5,000 tokens»; символьний еквівалент виміряно по транскриптах) —
#     зміниться харнес, переміряй, а не вір числам тут;
#   · --trigger бачить лише Edit/Write (Bash-правки домену — ні); домен — грубий регекс
#     шляху; «завантажено» = виклик Skill · інʼєктоване тіло (маркер нижче; його несе й
#     `invoked_skills` після компакції) · Read SKILL.md · Bash-читання SKILL.md, а `wc -c`
#     читанням НЕ є; «промах» ≠ «шкода» — шкоду міряє лише читання транскрипту;
#   · --reorder доводить нульову втрату РЯДКІВ і сліпий до позиційних слів («нижче»,
#     «below», «вище»), що після перестановки можуть показувати не туди — грепни їх сам.

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SKILLS = File.join(ROOT, ".claude/skills")
LISTING_CAP = 1536 # видимі 1535 символів + «…»
COMPACTION_CUT = 19_900 # символів тіла, що повертаються після компакції
SKILL_NAME = /[a-z0-9-]+/ # 🔴 з цифрами: без них `web3-pipeline` невидимий
LOADED_MARK = %r{Base directory for this skill: \S*?/\.claude/skills/(#{SKILL_NAME})}
# Харнес іменує каталог проєкту шляхом, де КОЖЕН не-алфанумеричний символ став «-»
# (і `_` теж: `silken_net` → `silken-net`) — інакше прилад тихо міряє порожнечу.
TRANSCRIPTS = ENV.fetch("SKILL_PROBE_TRANSCRIPTS") do
  File.join(Dir.home, ".claude/projects", ROOT.gsub(/[^A-Za-z0-9]/, "-"))
end
MEMORY_DIR = File.join(TRANSCRIPTS, "memory")

# Грубі регекси шляху на домен; уточнюй тут, коли домен переїжджає.
DOMAINS = {
  "frontend" => %r{/app/(views/components|javascript/controllers|assets/tailwind)/},
  "backend" => %r{/app/(models|policies|controllers/api)/},
  "web3-pipeline" => %r{/(contracts/[^/]+\.sol|app/services/(web3|blockchain|minting)[^/]*/?)},
  "telemetry-pipeline" => %r{/app/(workers/unpack|services/telemetry)},
  "deploy" => %r{/(terraform/|deploy/|config/deploy[^/]*\.yml)},
  "firmware" => %r{/firmware/(soldier|queen|common|bio_contracts)/},
  "legal-business" => %r{/docs/(protocols/(legal|business|outreach)/|00_0[24]_)},
  "ssot-maintenance" => %r{/docs/\d\d_\d\d_[^/]+\.md$},
  "memory-maintenance" => /#{Regexp.escape(MEMORY_DIR)}/o,
  "picogk" => %r{/tools/cad/},
  "in-silico" => %r{/(tools/in_silico|docs/protocols/ebfc/in_silico)/},
  "ml-engineering" => %r{/tools/ml/}
}.freeze

def frontmatter_and_body(path)
  src = File.read(path)
  fm = src[/\A---\n(.*?)\n---\n/m, 1] or abort "#{path}: no frontmatter"
  [ YAML.safe_load(fm), src.sub(/\A---\n.*?\n---\n/m, "") ]
end

def listing
  puts "СЛІПОТА: стеля #{LISTING_CAP} і зріз #{COMPACTION_CUT} — виміряні константи харнесу; позиція — у символах тіла."
  Dir[File.join(SKILLS, "*/SKILL.md")].sort.each do |f|
    y, body = frontmatter_and_body(f)
    desc = "#{y["description"]}#{y["when_to_use"]}".length
    lost = [ body.length - COMPACTION_CUT, 0 ].max
    printf("%-20s desc %4d%s  body %6d  past cut %3d%%\n", y["name"], desc, desc >= LISTING_CAP ? " OVER" : "",
           body.length, 100 * lost / body.length)
    body.scan(%r{<!-- /([A-Z0-9-]+) -->}) { |(n)| printf("    index %-28s ends %6d%s\n", n, $~.end(0), $~.end(0) > COMPACTION_CUT ? " ⚠ past cut" : "") }
    Dir[File.join(File.dirname(f), "*.md")].reject { |c| c.end_with?("/SKILL.md") }.sort.each do |c|
      at = body.index(File.basename(c))
      printf("    names %-28s at   %s\n", File.basename(c), at || "never")
    end
  end
end

def skill_reads(cmd)
  return [] unless cmd.match?(/\b(cat|sed|head|tail|awk|less)\b/)

  out = cmd.scan(%r{\.claude/skills/(#{SKILL_NAME})/SKILL\.md}).flatten
  # 🔴 форма з дужками; розгортати лише всередині шляху скіла — наївне розгортання
  # вибухає на Ruby-блоках у командах і висить.
  cmd.scan(%r{\.claude/skills/\{([a-z0-9,-]+)\}/SKILL\.md}) { |(g)| out.concat(g.split(",")) }
  out
end

def session_events(file)
  loads = {}
  first = {}
  compacts = []
  File.foreach(file) do |line|
    if line.include?("compact_boundary")
      j = JSON.parse(line) rescue nil
      compacts << j["timestamp"].to_s if j
      next
    end
    next unless line.include?("skills") || line.include?('"Edit"') || line.include?('"Write"')

    j = JSON.parse(line) rescue next
    ts = j["timestamp"].to_s
    line.scan(LOADED_MARK) { |(s)| loads[s] ||= ts }
    content = j.dig("message", "content")
    next unless content.is_a?(Array)

    content.each do |c|
      next unless c.is_a?(Hash) && c["type"] == "tool_use"

      path = c.dig("input", "file_path").to_s
      loads[$1] ||= ts if c["name"] == "Read" && path =~ %r{\.claude/skills/(#{SKILL_NAME})/SKILL\.md$}
      skill_reads(c.dig("input", "command").to_s).each { |s| loads[s] ||= ts } if c["name"] == "Bash"
      next unless %w[Edit Write].include?(c["name"]) && !path.include?("/.claude/skills/")

      DOMAINS.each { |s, re| first[s] ||= ts if path.match?(re) }
    end
  end
  [ loads, first, compacts.min ]
end

def trigger
  files = Dir[File.join(TRANSCRIPTS, "*.jsonl")]
  abort "no transcripts under #{TRANSCRIPTS}" if files.empty?
  puts "СЛІПОТА: лише Edit/Write; домен — регекс шляху; промах ≠ шкода (шкоду міряє аудит наслідків). Сесій: #{files.size}."
  tab = Hash.new { |h, k| h[k] = Hash.new(0) }
  files.each do |f|
    loads, first, compact = session_events(f)
    first.each do |s, ts|
      phase = compact && compact < ts ? :post : :pre
      tab[s][:"#{phase}_n"] += 1
      tab[s][:"#{phase}_miss"] += 1 unless loads[s] && loads[s] <= ts
    end
  end
  puts "domain               before-compaction miss/n   after-compaction miss/n"
  DOMAINS.each_key do |s|
    t = tab[s]
    printf("%-20s %8d/%-3d %22d/%-3d\n", s, t[:pre_miss], t[:pre_n], t[:post_miss], t[:post_n])
  end
end

def reorder(file, order)
  abort "usage: --reorder FILE HEADING…" if file.nil? || order.empty?
  src = File.read(file)
  fm = src[/\A---\n.*?\n---\n/m] or abort "no frontmatter"
  body = src[fm.length..]
  chunks = [ [ nil, +"" ] ]
  body.each_line do |l|
    chunks << [ l.strip, +"" ] if l.start_with?("## ")
    chunks.last[1] << l
  end
  pre, *secs = chunks
  picked = order.map do |p|
    hits = secs.select { |h, _| h.start_with?("## #{p}") }
    abort "#{p.inspect} matched #{hits.size} sections" unless hits.size == 1
    hits.first
  end
  rest = secs - picked
  new_body = "#{pre[1].sub(/\n*\z/, "\n\n")}#{(picked + rest).map { |_, t| t.sub(/\n*\z/, "") }.join("\n\n")}\n"
  lines = ->(s) { s.lines.map(&:chomp).reject(&:empty?).sort }
  abort "LOSS: the multiset of non-empty lines differs — nothing written" unless lines.(body) == lines.(new_body)
  File.write(file, fm + new_body)
  puts "СЛІПОТА: доведено нульову втрату РЯДКІВ; позиційні слова («нижче», «below») перевір сам."
  pos = 0
  new_body.each_line do |l|
    puts "#{pos.to_s.rjust(6)} #{l[0, 70]}" if l.start_with?("## ") || l.include?(":AUTO")
    pos += l.length
  end
end

case ARGV.first
when "--listing" then listing
when "--trigger" then trigger
when "--reorder" then reorder(ARGV[1], ARGV[2..] || [])
else abort "usage: ruby scripts/skill_tier_probe.rb --listing | --trigger | --reorder FILE HEADING…"
end
