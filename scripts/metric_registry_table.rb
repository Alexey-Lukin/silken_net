#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [INF.26] Регенерація канонічного реєстру метрик у `docs/06_03` §2.8.
#
# 🔴 НАВІЩО СКРИПТ, а не однорядковик, який тут стояв. Доти рецепт казав
# «регенерувати ЛИШЕ цю таблицю», і команда друкувала рядок ЦІЛКОМ — тобто
# ПЕРЕЗАПИСУВАЛА колонку `Призначення`. Вимір 2026-08-29: дванадцять із комірок
# дописані руками поверх докстрінга (до +1210 символів на рядок) — там живуть
# підстави присудів, а не переказ. Тобто задокументована процедура, виконана
# ДОСЛІВНО, тихо знищувала канон, і жоден гейт цього не бачив: вони судять імена
# й типи, ніколи прозу (§Guard-craft #115).
#
# 🔑 Присуд, який знімає клас: колонки розділені за ВЛАСНІСТЮ.
#   · `Metric` · `Ярус` · `Labels` — ВИВЕДЕНІ з коду, скрипт їх переписує завжди;
#   · `Призначення`               — КАНОН-ПРОЗА, дім тут. Скрипт її НЕ чіпає
#                                   ніколи; для НОВОГО рядка засівається докстрінгом.
#
# ⚠️ ОГОЛОШЕНА СТЕЛЯ: скрипт не судить, чи проза ще правдива — лише не дає її
# затерти. Розходження «докстрінг сказав одне, комірка інше» лишається на очах
# ревʼювера, і це свідомо: злити їх означало б або втратити прозу, або зробити
# докстрінг (він їде в /metrics HELP по дроту) канон-довжини.
#
#   ruby scripts/metric_registry_table.rb            # dry-run: показати, чи розійшлось
#   ruby scripts/metric_registry_table.rb --write    # застосувати
#
# Ярус метрики читається з докстрінга: `[… diagnostic tier: <подія> ]` →
# «діагностична», інакше «алертна». Дім правила — `06_03 §2.8`, гейт —
# `spec/quality/metric_registry_doc_sync_spec.rb`.

require "pathname"

ROOT = Pathname.new(File.expand_path("..", __dir__))
DOC = ROOT.join("docs/06_03_Prometheus_Observability.md")
SECTIONS = { counter: "Counters", gauge: "Gauges", histogram: "Histograms" }.freeze
HEADER = "| Metric | Ярус | Labels | Призначення |\n|---|---|---|---|\n"
COLUMNS = 4

require_relative "../config/initializers/prometheus" unless defined?(SilkenNet::Metrics::REGISTRY)

# Тіло однієї канонічної таблиці — від власної шапки до наступної. Той самий вираз,
# що в спеці-гейті.
#
# 🔴 СКОУП НЕСУЧИЙ, і обидва його порушення вже траплялись за один прохід.
# Підсекції §2.3–§2.7 несуть ВЛАСНІ таблиці з іншим розкладом колонок (там є
# `Constant` і `Source`), тож файловий скан домішує їх: спершу до видобування
# прози, потім до гарда, який від того червонів на цілком здорових рядках.
def table_body(doc, label)
  labels = SECTIONS.values.join("|")
  body = doc[/^\*\*#{label}[^:]*:\*\*(.*?)(?=^\*\*(?:#{labels})[^:]*:\*\*|\A\z|^---$)/m, 1]
  raise "у #{DOC.basename} немає таблиці `**#{label}:**`" if body.nil?

  body
end

def metric_rows(doc)
  SECTIONS.values.flat_map { |label| table_body(doc, label).lines }
          .select { |line| line.start_with?("| `silkennet_") }
end

# Наявні комірки `Призначення`, ключовані іменем метрики — ЄДИНЕ, що переживає прогін.
#
# 🔴 Поле беремо ПОЗИЦІЙНО від кінця, і це не стиль. Перша редакція читала прозу
# регексом `\|.*?\|\s*(.*?)\s*\|$`, і він мовчки міняв значення, щойно в рядку
# ставало на колонку більше: на вже-регенерованому рядку `.*?` захоплював
# `Labels | Призначення` як прозу, і другий прогін ЗАДВОЮВАВ колонку `Labels`.
# Скрипт був НЕідемпотентний, а перевірка «чи вціліла проза» цього не бачила, бо
# міряла те саме останнє поле. Ідемпотентність тепер стереже гард нижче.
def existing_prose(doc)
  metric_rows(doc).to_h do |line|
    [ line[/`(silkennet_[a-z0-9_]+)`/, 1], line.chomp.split("|", -1)[-2].to_s.strip ]
  end
end

def tier(metric) = metric.docstring.match?(/diagnostic tier:/) ? "діагностична" : "алертна"

def labels_of(metric)
  labels = metric.instance_variable_get(:@labels) || []
  labels.empty? ? "—" : labels.map { |l| "`#{l}`" }.join(", ")
end

def row(metric, prose) = "| `#{metric.name}` | #{tier(metric)} | #{labels_of(metric)} | #{prose} |"

doc = DOC.read
prose = existing_prose(doc)
rebuilt = doc.dup
seeded = []

SECTIONS.each do |kind, label|
  metrics = SilkenNet::Metrics::REGISTRY.metrics.select { |m| m.type == kind }.sort_by { |m| m.name.to_s }
  body = metrics.map do |m|
    text = prose[m.name.to_s]
    seeded << m.name.to_s if text.nil?
    row(m, text || m.docstring)
  end.join("\n")

  old_body = table_body(rebuilt, label)
  rebuilt = rebuilt.sub("**#{label}:**#{old_body}", "**#{label}:**\n\n#{HEADER}#{body}\n\n")
end

# ⛔ Гард ідемпотентності: кожен рядок КАНОНІЧНИХ таблиць мусить мати рівно чотири
# колонки. Без нього неідемпотентний екстрактор тихо доростає стовпчик за прогін, а
# жоден гейт цього не бачить — вони судять першу колонку й другу.
bad = metric_rows(rebuilt).reject { |l| l.chomp.split("|", -1).size == COLUMNS + 2 }
raise "рядок не з #{COLUMNS} колонок (екстрактор зʼїхав):\n#{bad.first(3).join}" unless bad.empty?

if rebuilt == doc
  puts "✓ таблиці вже в паритеті з реєстром — нічого не змінилось"
  exit 0
end

if ARGV.include?("--write")
  DOC.write(rebuilt)
  puts "✓ записано #{DOC.relative_path_from(ROOT)}"
  puts "  нових рядків, засіяних докстрінгом: #{seeded.size}#{seeded.empty? ? '' : " (#{seeded.join(', ')})"}"
  puts "  ⚠️ проза наявних рядків НЕ чіпалась — це канон, не згенероване"
else
  puts "dry-run: таблиці розійшлись із реєстром. Прогони з `--write`."
  puts "  нових рядків буде засіяно докстрінгом: #{seeded.size}#{seeded.empty? ? '' : " (#{seeded.join(', ')})"}"
  exit 1
end
