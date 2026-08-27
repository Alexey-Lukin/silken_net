#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Advisory-звіти по `00_07` — **НЕ гейти** [DOC-T.92].
#
# Обидва режими нижче стережуть осі, на яких HARD-гейт було ВИМІРЯНО й ВІДМОВЛЕНО, і
# відмова записана, щоб не перевідкривалась:
#
#   · **доступність роботи.** Дискримінатор семантичний: гейт бачив би `🤖`-лід і не
#     бачив би `(demand-gated)` чи «після присуду» в прозі того ж рядка, тож був би
#     бездоганно зеленим над роботою, робити яку заборонено. Вердикт дає READ тіла.
#   · **`🚦 Critical Path`.** Сира точність «архівний ID у рядку Critical Path» — 4 з 14
#     (29%); звужена форма давала 80%, але exclusion-лист виведено ІЗ ТИХ САМИХ 14, тобто
#     in-sample, і числу вірити не можна. Носій лишається advisory + правило в
#     `.claude/prompts/deep_archival.md` («архівуючи ID, грепни його в `🚦`»).
#
# 🔴 **Обидва режими друкують ВЛАСНУ сліпоту ПЕРЕД результатом, і це не ввічливість.**
# Звіт, чиї числа правдиві над КУРОВАНОЮ множиною, є палантіром (`00_05 §7`): Саурон не
# підробив жодного зображення — він керував тим, ЩО показувалось. Тут той самий ризик:
# лічильник «вільних ніг» точний рівно настільки, наскільки повний перелік форм
# відкладення, а той перелік — рукописний.
#
# Pure Ruby, без Rails. Ростер режимів — `case` нижче; читати його, а не цю шапку.
#   ruby scripts/tracker_report.rb --takeable
#   ruby scripts/tracker_report.rb --critical-path
# Exit 0 ЗАВЖДИ (окрім помилки аргументів): це звіт, а не вердикт.

require_relative "../lib/tracker/dashboard"

D = Tracker::Dashboard

# Форми ВІДКЛАДЕННЯ, що трапляються в прозі ноги. Перелік рукописний і саме тому
# друкується читачеві: усе, чого тут немає, порахується ВІЛЬНИМ, тож число «вільних» є
# ВЕРХНЬОЮ межею. Виведено з корпусу (не з голови) — кожна форма має живі входження.
DEFERRAL_FORMS = {
  "demand-gated" => /demand[-\s]?gated/i,
  "після присуду" => /післ\p{L}*\s+(?:⚖️\s*)?присуд/i,
  "після <події>" => /\bпісля\s/i,
  "bench" => /\bbench\b/i,
  "gated" => /gated/i,
  "чекає" => /чека[єю]/i,
  "⛔ у самій нозі" => /⛔/,
  "коли · щойно" => /\b(?:коли|щойно)\s/i,
  "блокується" => /блоку[єʼ']/i,
  "не раніше" => /не раніше/i,
  "потребує" => /потребу[єю]/i,
  "TBD" => /\bTBD\b/
}.freeze

def sections(markdown)
  current = nil
  markdown.each_line.with_object(Hash.new { |h, k| h[k] = [] }) do |line, acc|
    if line.start_with?("## ")
      current = line.match?(D::REGISTRY_SECTION) && !line.match?(D::SKIP_SECTION) ? line[/## (§\S+)/, 1] : nil
      next
    end
    acc[current] << line if current
  end
end

# [section, id, lead, body] для кожної ВІДКРИТОЇ ноги — той самий скоуп, що в
# `item_residuals`; секція додається окремим проходом, бо `item_residuals` її не несе.
def open_legs(markdown)
  by_section = sections(markdown)
  D.item_residuals(markdown).flat_map do |it|
    section = by_section.find { |_, lines| lines.any? { |l| l.match(D::ITEM_HEAD)&.captures&.first == it[:id] } }&.first
    it[:open].map { |b| { section:, id: it[:id], lead: b[D::WHO_LEAD].to_s, body: b } }
  end
end

def deferred?(body) = DEFERRAL_FORMS.any? { |_, re| body.match?(re) }

def takeable_report(markdown)
  legs = open_legs(markdown)
  unrecognised = legs.reject { |l| l[:lead].empty? || l[:lead].match?(D::WHO_GLYPH) }

  puts "tracker:takeable — ЗВІТ, не гейт. Числа правдиві; МНОЖИНА КУРОВАНА."
  puts
  puts "⚠️  СПЕРШУ ПРО ВЛАСНУ СЛІПОТУ — читати ДО результату:"
  puts "  · гліф-вісь ТОЧНА: словник ліда закритий і гейтований (`residual_lead_form`),"
  puts "    нерозпізнаних лідів зараз #{unrecognised.size}."
  puts "  · проза-вісь ЕВРИСТИЧНА: знає #{DEFERRAL_FORMS.size} форм відкладення (нижче), і все, чого"
  puts "    в переліку НЕМАЄ, рахується ВІЛЬНИМ. Отже «вільних» — це ВЕРХНЯ МЕЖА, ніколи точне число."
  puts "  · `⛔` та присуди в `**Стан:**` ПУНКТА цей фільтр не читає взагалі — заборона рівня"
  puts "    пункту тут невидима, і саме вона найчастіше і є справжнім гейтом."
  puts "  · вердикт «чи цю ногу можна брати» дає READ тіла пункту. Тут — КАНДИДАТИ."
  puts "  · форми, які фільтр знає: #{DEFERRAL_FORMS.keys.join(' · ')}"
  puts

  rows = legs.group_by { |l| l[:section] }.sort_by { |s, _| s.to_s }
  puts format("%-8s %10s %10s %10s %10s", "секція", "гліф", "∖проза", "🤖 гліф", "🤖 ∖проза")
  totals = Hash.new(0)
  rows.each do |section, ls|
    glyph = ls.count { |l| l[:lead].match?(D::WHO_GLYPH) }
    free  = ls.count { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) }
    mglyph = ls.count { |l| l[:lead].include?("🤖") }
    mfree  = ls.count { |l| l[:lead].include?("🤖") && !deferred?(l[:body]) }
    totals[:glyph] += glyph
    totals[:free] += free
    totals[:mglyph] += mglyph
    totals[:mfree] += mfree
    puts format("%-8s %10d %10d %10d %10d", section, glyph, free, mglyph, mfree)
  end
  puts format("%-8s %10d %10d %10d %10d", "УСЬОГО", totals[:glyph], totals[:free], totals[:mglyph], totals[:mfree])
  puts
  ratio = totals[:mfree].zero? ? nil : (totals[:mglyph].to_f / totals[:mfree])
  puts "🔑 Множник завищення по `🤖`-осі: #{ratio ? format('×%.1f', ratio) : 'н/д'} — тобто скан за самим гліфом"
  puts "   бачить у стільки разів більше машинної роботи, ніж лишається після прози. Число"
  puts "   є ВЛАСТИВІСТЮ ЗРІЗУ: по секціях воно різне, тож цитувати його можна лише з прогону."
  puts "   ⚠️ ОДИНИЦЯ — НОГА, не пункт. Множник, порахований по ПУНКТАХ (скільки items несуть"
  puts "   сольний `🤖` проти скількох справді вільні), — інше число над іншою множиною; два"
  puts "   такі множники правдиві одночасно й НЕ взаємозамінні."
  puts

  dry = rows.reject { |_, ls| ls.any? { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) } }
  if dry.empty?
    puts "Секцій, де після прози не лишилось ЖОДНОЇ вільної ноги: немає."
  else
    puts "Секції, де після прози не лишилось ЖОДНОЇ вільної ноги (#{dry.size}): #{dry.map(&:first).join(', ')}"
  end

  by_item = legs.group_by { |l| l[:id] }
  stuck = by_item.reject { |_, ls| ls.any? { |l| l[:lead].match?(D::WHO_GLYPH) && !deferred?(l[:body]) } }
  puts "Пунктів, де `гліф ∖ проза` = 0 (усе відкрите виглядає відкладеним): #{stuck.size}"
  stuck.keys.sort.each_slice(12) { |s| puts "  #{s.join(' · ')}" }
end

def critical_path_report(markdown)
  live = D.parse(markdown).map(&:id).to_set
  all  = D.all_item_ids(markdown).to_set
  archived = all - live

  in_cp = []
  in_section = false
  markdown.each_line do |line|
    if line.start_with?("## ")
      in_section = line.start_with?("## 🚦")
      next
    end
    next unless in_section

    line.scan(/(?<![A-Za-z0-9_])([A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-][0-9A-Za-z.\-]+)/) do |id,|
      in_cp << id.sub(/[.\-]+\z/, "")
    end
  end
  in_cp.uniq!

  puts "tracker:critical-path — ЗВІТ, не гейт. Кандидати, НЕ вердикт."
  puts
  puts "⚠️  ВЛАСНА СЛІПОТА, названа першою:"
  puts "  · сира точність цієї осі ВИМІРЯНА і низька — 4 справжні з 14 (29%). Більшість"
  puts "    цитувань архівного ID у `🚦` законні: корпус посилається на закриті пункти як на"
  puts "    ПРОВЕНАНС («ex-…», «поглинув …»), і це не борг."
  puts "  · звужену форму (80%) відхилено, бо exclusion-лист був виведений із ТІЄЇ САМОЇ"
  puts "    чотирнадцятки — in-sample, тобто число описує підгонку, а не точність."
  puts "  · тому це advisory назавжди; правило-носій живе в `.claude/prompts/deep_archival.md`."
  puts

  hits = in_cp.select { |id| archived.include?(id) }.sort
  puts "ID у `🚦 Critical Path`: #{in_cp.size} · з них архівних: #{hits.size}"
  puts
  if hits.empty?
    puts "Архівних ID у рядках Critical Path не знайдено."
  else
    puts "Кандидати (кожен ЧИТАТИ очима — інваріант «закритий елемент ВИПАДАЄ з рядка»):"
    hits.each { |id| puts "  · #{id}" }
  end
end

MODE = ARGV.find { |a| a.start_with?("--") } || "--takeable"
md = File.read(D::DEFAULT_PATH)

case MODE
when "--takeable"      then takeable_report(md)
when "--critical-path" then critical_path_report(md)
else
  warn "невідомий режим #{MODE}. Ростер: --takeable · --critical-path"
  exit 2
end
