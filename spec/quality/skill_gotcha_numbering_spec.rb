# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# 🔴 Нумерований ряд гоч скіла не сміє виходити ЗА свою секцію.
#
# Механізм, і чому це не косметика. Гочі нумеровані, і на ці номери ключуються
# ЗОВНІШНІ цитати — памʼять, канон і сусідні скіли посилаються «`backend` #26a»,
# «`frontend` #12». Читач іде в секцію «Gotchas», доходить до її кінця й вважає
# перелік повним. Якщо частина ряду осіла нижче — під `## Common Tasks` або під
# `## Keep Bounded`, тобто під заголовком, який прямо велить НЕ реставляти, —
# він бачить лише першу половину, і невидимою стає саме СВІЖА половина: нові
# гочі дописуються в кінець ФАЙЛУ, а не в кінець секції.
#
# Дефект створюється природним жестом, а не помилкою судження: «допиши гочу
# внизу» — найдешевша дія, і вона щоразу трохи зсуває межу. Ревʼю тут структурно
# немає (файл читають посекційно), тож без носія рецидив — питання часу, а не
# ймовірності. Саме тому це гейт, а не рядок у прозі (`feedback_rule_needs_a_carrier`).
#
# Улов на момент написання — 0, і це навмисно: гейт ставиться ПІСЛЯ фіксу
# (DOC-T.80 повернув `backend` #56–71 у секцію, зберігши номери). Поставлений
# раніше, він давав би вічно-червону стійку, яка навчає скіпати
# (`ssot-maintenance` §Guard-craft #62 — вимірювач першим, але червоним по
# ПЕРИМЕТРУ кампанії, а не назавжди).
#
# 🔴 ДИСКРИМІНАТОР — «ряд ПРОДОВЖУЄ той самий лік», не «є нумерація поза секцією».
# Різниця несуча й куплена виміром: наївний скан «нумерований рядок поза секцією
# гоч» дає хіти у ТРЬОХ скілах, з яких два законні — `deploy` і `factory-flashing`
# відкривають після гоч НОВІ ряди («1. Docs-first», «1. grep/read Session»), тобто
# кроки правил і рецептів. Ряд, що починається з 1, — власний; ряд, що починається
# з 56 при секції, яка скінчилась на 55, — відрізаний хвіст чужого.
#
# 🔒 Стелі, названі чесно:
#   · Судиться лише скіл, що МАЄ секцію гоч (заголовок `##` зі словом
#     Gotcha/гоча). Скіл без такої секції поза периметром — там ряду немає.
#   · Судиться ПЕРШИЙ номер ряду, ніколи його зміст і ніколи порядок усередині
#     секції: `25b` перед `25a` всередині гоч цей гейт НЕ бачить і не має бачити
#     (перенумерування заборонене — номери є адресами).
#   · Ряди в fenced-блоках пропускаються: нумерований рядок у прикладі коду не є
#     розміткою документа.
#   · Гейт не питає, чи гоча ДОРЕЧНА у своїй секції — лише де вона лежить.
module SkillGotchaNumbering
  ROOT = REPO_ROOT
  SCAN_GLOB = ".claude/skills/*/SKILL.md"

  HEADING_RE  = /\A##+\s/
  SECTION_RE  = /\A##+\s.*(?:gotcha|гоч)/i
  NUMBERED_RE = /\A(\d+)([a-z]?)\.\s/
  FENCE_RE    = /\A\s*```/

  Row = Struct.new(:num, :suffix, :lineno, :text, keyword_init: true)

  # Нумеровані рядки файлу поза fenced-блоками, з номером рядка.
  def self.numbered_rows(lines)
    in_fence = false
    lines.each_with_index.filter_map do |line, idx|
      in_fence = !in_fence if line =~ FENCE_RE
      next if in_fence
      next unless (m = line.match(NUMBERED_RE))

      Row.new(num: m[1].to_i, suffix: m[2], lineno: idx + 1, text: line.strip[0, 70])
    end
  end

  # Межі секції гоч: [перший рядок після заголовка, рядок наступного ## )
  def self.gotcha_span(lines)
    start = lines.index { |l| l =~ SECTION_RE }
    return nil unless start

    rest  = lines[(start + 1)..] || []
    offset = rest.index { |l| l =~ HEADING_RE }
    finish = offset ? start + 1 + offset : lines.size
    [ start + 1, finish ]
  end

  # Розбиває послідовність рядів на ГРУПИ: новий ряд починається там, де
  # номер не більший за попередній (лік пішов спочатку).
  def self.runs(rows)
    rows.each_with_object([]) do |row, acc|
      if acc.empty? || row.num <= acc.last.last.num
        acc << [ row ]
      else
        acc.last << row
      end
    end
  end

  def self.violations
    Dir.glob(ROOT.join(SCAN_GLOB)).sort.flat_map do |path|
      lines = File.readlines(path)
      span  = gotcha_span(lines)
      next [] unless span

      _, finish = span
      rows = numbered_rows(lines).select { |r| r.lineno > finish }
      skill = File.basename(File.dirname(path))

      runs(rows).reject { |run| run.first.num == 1 }.map do |run|
        nums = run.map { |r| "#{r.num}#{r.suffix}" }.join(", ")
        "#{skill}: ряд [#{nums}] стоїть ПІСЛЯ секції гоч " \
          "(#{path.sub(ROOT.to_s + "/", "")}:#{run.first.lineno}) — #{run.first.text}"
      end
    end
  end

  # Ліхтар популяції: скіли, що взагалі мають нумеровані гочі В секції.
  def self.skills_with_numbered_gotchas
    Dir.glob(ROOT.join(SCAN_GLOB)).count do |path|
      lines = File.readlines(path)
      span  = gotcha_span(lines)
      next false unless span

      from, to = span
      numbered_rows(lines).any? { |r| r.lineno > from && r.lineno < to }
    end
  end
end

RSpec.describe "нумерований ряд гоч живе у своїй секції [DOC-T.80]" do
  # Без цього прикладу «нуль порушень» не відрізнити від «нуль перевірок»:
  # порожня множина тут МЕТА, тож живість доводиться популяцією окремо
  # (`ssot-maintenance` §Guard-craft #61).
  it "має непорожню популяцію скілів із нумерованими гочами" do
    expect(SkillGotchaNumbering.skills_with_numbered_gotchas).to be >= 5
  end

  it "не має ряду, що продовжує лік гоч ПОЗА своєю секцією" do
    offenders = SkillGotchaNumbering.violations

    expect(offenders).to be_empty, <<~MSG
      Нумерований ряд гоч виходить за межі секції «Gotchas»:

      #{offenders.join("\n")}

      ЧОМУ це ловиться: читач відкриває секцію гоч, бачить її кінець і вважає
      перелік повним — а винесена частина невидима, і це завжди СВІЖА частина
      (нове дописують у кінець файлу).

      ЛІК — перемістити блоки НАЗАД у секцію, ЗБЕРІГШИ номери: на них ключуються
      зовнішні цитати з памʼяті, канону й сусідніх скілів («`backend` #26a»).
      ⛔ НЕ перенумеровувати. Операція масова, тож роби її скриптом із доказом
      zero-loss (множина непорожніх рядків до і після — ідентична), а не руками.

      Якщо ж це ВЛАСНИЙ ряд (кроки рецепту, правила) — він мусить починатися з 1,
      і тоді гейт мовчить за побудовою.
    MSG
  end
end
