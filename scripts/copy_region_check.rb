#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Copy-region guard — репо-маркери в тексті, що йде НАЗОВНІ [DOC-T.109]
#
# ПРЕДМЕТ. Листи в `docs/protocols/**` мають copy-регіон: усе після рядка
# «⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА» засновник надсилає постачальнику ДОСЛІВНО.
# Це людино-виконуваний артефакт без компілятора — його перший «прогін»
# відбувається на підлозі вендора, і помилку там ловить постачальник або ніхто.
# Доти цього маркера не читав ЖОДЕН скрипт, workflow чи скіл.
#
# МЕЖІ БЕРУТЬСЯ З ФАЙЛУ, не з цього скрипта:
#   * початок  — рядок ПІСЛЯ маркера «⬇️ КОПІЮВАТИ …»;
#   * кінець   — рядок «⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА» (НЕ входить), інакше наступний
#     `## `-заголовок або EOF. ⚠️ Перша редакція цього скрипта знала лише другу
#     половину межі й дала ШІСТЬ хибних позитивів на самому маркері кінця —
#     «межу бере з файлу» означає ОБИДВА його маркери, не один;
#   * МОВА     — найближчий попередній `## `-заголовок із `(EN)` чи `(UA)`.
# Регіон без оголошеної мови — ПОМИЛКА, а не пропуск: судити кирилицю в ньому
# нема на чому, і мовчазний пропуск був би зеленим кольором над невиміряним.
#
# ЩО СУДИТЬ (форма, не істина):
#   1. живий трекер-ID       — словник НЕ вигадано тут: токен + `Tracker::Dashboard`
#   2. `§`-реф               — адреса нашого канону; вендор її не резолвить
#   3. ISO-дата              — внутрішній провенанс
#   4. статус/присуд-гліфи   — мова трекера
#   5. репо-шлях             — `docs/`, `tools/`, `scripts/` …
#   6. кирилиця в EN-регіоні — і дзеркально латиниця НЕ судиться в UA (Ti-6Al-4V,
#      ISO, ASTM, назви вендорів там законні)
#
# ⛔ ОГОЛОШЕНА СТЕЛЯ, і без неї зелений почне означати «не перевірено».
# Гейт бачить лише МЕХАНІЧНУ половину класу. Третя знахідка ручного виміру
# 2026-09-13 — фраза «point values within these ranges», що стала хибною після
# виміру насичення соку, — не має жодної статичної прикмети: правильна мова,
# жодного репо-токена, бездоганний вигляд. Такий дефект ловить лише читання
# листа проти його канон-дому. Зелений тут НЕ є твердженням, що лист правдивий.
#
# Прогін: `ruby scripts/copy_region_check.rb` (exit 1 = знахідки)
#         `--list` — показати знайдені регіони та їхні межі, без суду

require "set"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "tracker/dashboard"

ROOT      = File.expand_path("..", __dir__)
PERIMETER = File.join(ROOT, "docs", "protocols", "**", "*.md")
MARKER    = "КОПІЮВАТИ ВІД ЦЬОГО РЯДКА"
END_MARK  = "КІНЕЦЬ ТЕКСТУ ЛИСТА"

# Той самий токенізатор, що в `code_tracker_id_check.rb` — ID-словник має ОДИН дім.
TOKEN_RE = %r{(?<![A-Za-z0-9_])[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-]\d[0-9A-Za-z.]*(?:-[A-Z0-9.]+)*(?:/\d+(?![\d_]))*}
GLYPHS   = "⚪🟡🟢🔗🌿⚫🤖👤⚖️✅⛔🔴⚠️🔑🗄️🎯📊⊕⊥"
REPO_DIR = %w[docs tools scripts app lib spec firmware contracts config .claude .github].freeze

def regions(text)
  lines = text.lines
  out   = []
  lang  = nil
  start = nil
  lines.each_with_index do |line, idx|
    if line.include?(END_MARK)
      out << [start, idx - 1, lang] if start
      start = nil
    elsif line.start_with?("## ")
      out << [start, idx - 1, lang] if start
      start = nil
      lang  = line[/\((EN|UA)\)/, 1]
    elsif line.include?(MARKER)
      start = idx + 1
    end
  end
  out << [start, lines.size - 1, lang] if start
  out
end

def violations(file, lines, from, to, lang, ids, facets)
  hits = []
  add  = ->(lineno, kind, sample) { hits << [file, lineno + 1, kind, sample] }

  (from..to).each do |i|
    line = lines[i]
    line.scan(TOKEN_RE) do |tok|
      next unless ids.include?(tok) ||
                  (base = tok[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*\.\d+/]) && base != tok &&
                    ids.include?(base) &&
                    facets.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(tok)}(?![0-9A-Za-z])/)

      add.call(i, "трекер-ID", tok)
    end
    add.call(i, "§-реф", line[/\S*§\S*/]) if line.include?("§")
    add.call(i, "ISO-дата", Regexp.last_match(0)) if line =~ /\b20\d{2}-\d{2}-\d{2}\b/
    GLYPHS.each_grapheme_cluster { |g| add.call(i, "гліф", g) if line.include?(g) }
    REPO_DIR.each { |d| add.call(i, "репо-шлях", "#{d}/") if line.include?("#{d}/") }
    if lang == "EN" && line =~ /\p{Cyrillic}/
      add.call(i, "кирилиця в EN", line.scan(/\p{Cyrillic}+/).first)
    end
  end
  hits
end

files = Dir[PERIMETER].select { |f| File.file?(f) }.sort
tracker_md = File.read(Tracker::Dashboard::DEFAULT_PATH)
ids        = Tracker::Dashboard.all_item_ids(tracker_md).to_set
facets     = Tracker::Dashboard.item_body_text(tracker_md)

list_only = ARGV.include?("--list")
all_hits  = []
undeclared = []
found_regions = 0

files.each do |path|
  text = File.read(path)
  next unless text.include?(MARKER)

  rel   = path.sub("#{ROOT}/", "")
  lines = text.lines
  regions(text).each do |from, to, lang|
    found_regions += 1
    puts format("  %s:%d-%d  мова=%s  (%d рядків)", rel, from + 1, to + 1, lang || "НЕ ОГОЛОШЕНА", to - from + 1) if list_only
    if lang.nil?
      undeclared << [rel, from + 1]
      next
    end
    all_hits.concat(violations(rel, lines, from, to, lang, ids, facets))
  end
end

if list_only
  puts "\nрегіонів: #{found_regions}"
  exit 0
end

if undeclared.any?
  puts "❌ Copy-регіон без оголошеної мови (заголовок `## … (EN)` чи `(UA)` перед маркером):"
  undeclared.each { |rel, ln| puts "   #{rel}:#{ln}" }
end

if all_hits.any?
  puts "❌ Репо-маркери всередині copy-регіону (цей текст їде вендорові дослівно):"
  all_hits.each { |file, ln, kind, sample| puts format("   %s:%d  %s — %s", file, ln, kind, sample) }
end

if all_hits.empty? && undeclared.empty?
  puts "✅ copy-регіони чисті (#{found_regions} регіонів у #{files.count { |f| File.read(f).include?(MARKER) }} файлах)"
  exit 0
end

exit 1
