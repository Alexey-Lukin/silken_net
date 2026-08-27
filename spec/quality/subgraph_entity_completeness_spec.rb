# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# 🔴 Не-nullable поле сутності, якого мапінг НЕ ПИШЕ, компілюється зелено й падає лише
# в graph-node — тобто дефект народжується відвантаженим і виявляється на індексері.
#
# ЦЕ ВИМІРЯНО, А НЕ ПЕРЕКАЗАНО (2026-08-28, OPS.36). Стеля `graph build` була оголошена в
# OPS.34 словами «компіляція судить ТИПИ мапінгу, ніколи семантику»; я підсадив мутанта —
# зняв присвоєння одного не-nullable поля — і `npx graph build` вийшов **EXIT 0** із
# «Build completed». Отже єдиний носій цього класу — статична перевірка, і ось вона.
#
# Ціна класу специфічна: субграф є поверхнею, з якої ESG-покупець і ISO-аудитор читають
# нашу емісію, тож «індексер відмовився зберегти рядок» означає ДІРУ В ІСТОРІЇ, а не
# зламаний локальний скрипт. І клас щойно подорожчав: симетрія `SlashingEvent` додала
# два НОВІ не-nullable поля, тобто рівно ту форму, проти якої тут стоїть гейт.
#
# 🔒 CEILING, три частини:
#  · судиться ПРИСВОЄННЯ, ніколи ЗНАЧЕННЯ — поле, якому присвоїли не те, лишається поза
#    скоупом (це вже семантика, і її дім — тест-шар мапінгу, `matchstick-as`, OPS.36);
#  · nullable-поля не судяться взагалі: їх пропуск легальний за схемою;
#  · `id` виключено — його дає конструктор, не присвоєння.
module SubgraphEntityCompleteness
  SCHEMA  = REPO_ROOT.join("subgraph/schema.graphql")
  MAPPING = REPO_ROOT.join("subgraph/src/mapping.ts")

  # `type X @entity(...) { … }` — тіло до першого `\n}` у нульовій колонці.
  ENTITY_RE = /type\s+(\w+)\s+@entity[^{]*\{(.*?)\n\}/m
  # `name: Type!` — коментар зрізається ПЕРЕД матчем, інакше `# …!` дає хибний хіт.
  FIELD_RE  = /\A(\w+)\s*:\s*([\w\[\]!]+)\z/

  # 🔴 ДВІ форми конструкції, і друга — не екзотика: `getProtocolFinancials` уживає
  # `financials = new ProtocolFinancials("1")` (без `let`, бо змінна вже оголошена).
  # Парсер, що знає лише першу, МОВЧИТЬ про другу, а мовчання читається як здоровʼя
  # (§Guard-craft #9/#75). Саме тому нижче стоїть ліхтар на ПОВНОТУ розбору.
  CONSTRUCT_RE = /(?:\blet\s+)?(\w+)\s*=\s*new\s+(\w+)\s*\(/
  NEW_ANY_RE   = /\bnew\s+(\w+)\s*\(/

  module_function

  def entities
    SCHEMA.read.scan(ENTITY_RE).to_h do |name, body|
      fields = body.each_line.filter_map do |line|
        m = line.sub(/#.*/, "").strip.match(FIELD_RE)
        next unless m && m[1] != "id"

        m[1] if m[2].end_with?("!")
      end
      [ name, fields ]
    end
  end

  # [{ entity:, line:, assigned: [] }] — присвоєння від конструкції до найближчого
  # термінатора: `.save()`, `return <local>`, або кінець функції (`}` у нульовій колонці).
  def constructions
    known = entities.keys
    lines = MAPPING.read.lines
    lines.each_with_index.filter_map do |line, i|
      m = line.match(CONSTRUCT_RE)
      next unless m && known.include?(m[2])

      local = m[1]
      assigned = []
      ((i + 1)...lines.size).each do |j|
        row = lines[j]
        break if row.include?("#{local}.save()") || row.match?(/\A\s*return\s+#{Regexp.escape(local)}\b/) || row.start_with?("}")

        a = row.match(/\A\s*#{Regexp.escape(local)}\.(\w+)\s*=/)
        assigned << a[1] if a
      end
      { entity: m[2], line: i + 1, assigned: }
    end
  end
end

RSpec.describe SubgraphEntityCompleteness, type: :quality do
  let(:entities) { described_class.entities }
  let(:constructions) { described_class.constructions }

  # 🔦 Ліхтар 1 — схема розібрана. Регекс, що перестав матчити, дав би «нуль розходжень»
  # над порожньою множиною.
  it "розбирає непорожню множину сутностей із їхніми не-nullable полями" do
    expect(entities.keys).to include("SlashingEvent", "GovernanceSlashEvent", "ProtocolFinancials")
    expect(entities.values.map(&:size)).to all(be_positive)
  end

  # 🔦 Ліхтар 2 — і саме він несучий: він доводить, що парсер бачить КОЖНУ конструкцію,
  # а не лише ту форму, яку автор мав перед очима. Порівнюється з сирою лічбою `new X(`
  # по відомих сутностях, тобто з незалежним виміром того самого предмета.
  it "розбирає КОЖНУ конструкцію сутності — обидві форми, без мовчазного пропуску" do
    raw = described_class::MAPPING.read.scan(described_class::NEW_ANY_RE).flatten
                                  .count { |n| entities.key?(n) }

    expect(constructions.size).to eq(raw)
    expect(constructions.map { |c| c[:entity] }).to include("ProtocolFinancials"), "форма без `let` пропущена"
  end

  it "кожне НЕ-NULLABLE поле присвоюється перед збереженням" do
    gaps = constructions.filter_map do |c|
      missing = entities.fetch(c[:entity], []) - c[:assigned]
      next if missing.empty?

      "mapping.ts:#{c[:line]} #{c[:entity]} — не присвоєно: #{missing.join(', ')}"
    end

    expect(gaps).to be_empty,
                    "Не-nullable поле без присвоєння компілюється ЗЕЛЕНО (виміряно) і падає в graph-node:\n  " +
                    gaps.join("\n  ")
  end
end
