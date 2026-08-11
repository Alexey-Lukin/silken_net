# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт РЕНДЕРОВНОСТІ типу: `decimal`-колонка (або аліас над нею) не сміє потрапляти
# в Phlex-блок голою, бо Phlex друкує `BigDecimal` ПОРОЖНІМ рядком (`04_04 §2`).
#
# Народився з дефекту, який жив на центральному екрані й був невидимий за побудовою
# (`00_07` ARCH.89): `Trees::Show` малював порожнім `text-6xl` Z-координату і баланс —
# під самотнім написом «SCC». Виміряно рендером, не виведено:
#   Float → «12.5» · Integer → «12» · String → «12.5» · nil → «» · BigDecimal → «».
# Тобто Phlex мовчки викидає рівно той тип, яким AR віддає КОЖНУ нашу `decimal`-колонку.
#
# 🔴 Дві пастки, через які дефект читався як полагоджений:
#   · фолбек `|| "---"` не спрацьовує НІКОЛИ (BigDecimal істинний), тож захист
#     виглядає написаним і не діє;
#   · `.round(2)` НЕ рятує — на BigDecimal він повертає BigDecimal. Рятують
#     `.to_f`/`.to_i`/`.to_s`, `.round` без аргументу, інтерполяція та i18n.
#
# ⚠️ Компонентна спека сліпа до класу, поки фікстура — `OpenStruct`: той віддає
# Ruby-`Float`, тож сюїта бачить число там, де прод малює порожнечу (`04_06 §B.2` BP #14).
RSpec.describe "Phlex не друкує BigDecimal", type: :model do
  # 🔴 Множини беруться з РАНТАЙМУ, не з рукописного переліку: інакше нова
  # `decimal`-колонка чи новий аліас випадуть із периметра мовчки.
  def decimal_names
    @decimal_names ||= begin
      Rails.application.eager_load!
      cols = ActiveRecord::Base.descendants.flat_map do |m|
        begin
          next [] if m.abstract_class?
          next [] unless m.table_exists?

          m.columns_hash.filter_map { |n, c| n if c.type == :decimal } +
            m.attribute_aliases.filter_map { |from, to| from if m.columns_hash[to]&.type == :decimal }
        rescue StandardError
          []
        end
      end
      cols.uniq
    end
  end

  # Конвертори, після яких у блок їде вже НЕ BigDecimal. `\.round\b(?!\()` —
  # саме без аргументу: `round` дає Integer, `round(2)` лишає BigDecimal.
  def safe_conversion = /\.to_f|\.to_i|\.to_s|\.round\b(?!\()|sprintf|format\(|number_/

  def bare_decimal_renders
    re_col = Regexp.union(decimal_names)

    Dir.glob(Rails.root.join("app/views/**/*.rb")).flat_map { |file|
      File.readlines(file).each_with_index.flat_map { |line, idx|
        line.to_enum(:scan, /\{([^{}]*)\}/).filter_map do
          match = Regexp.last_match
          expr  = match[1]

          # `#{…}` — інтерполяція, вона кличе `to_s`, тож безпечна.
          next if match.pre_match.end_with?("#")
          # `t(".key", amount: x)` — i18n теж інтерполює значення.
          next if expr.match?(/\A\s*t\(/)
          next unless expr.match?(/(?:^|[.\s(])(#{re_col})\b/)
          next if expr.match?(safe_conversion)

          "#{file.sub("#{Rails.root}/", '')}:#{idx + 1} → #{expr.strip}"
        end
      }
    }
  end

  it "перелічує decimal-колонки з рантайму, а не з рукописного списку" do
    # Liveness: без цього прикладу порожній перелік зробив би головний гейт
    # вакуумним — «нуль порушень» означало б «нуль перевірок».
    expect(decimal_names).to include("balance", "z_value", "total_funding")
    expect(decimal_names).to include("scc_balance", "total_value") # аліаси
  end

  it "не має жодного голого decimal у Phlex-блоці" do
    expect(bare_decimal_renders).to be_empty, <<~MSG
      Phlex друкує BigDecimal ПОРОЖНІМ рядком — ці вузли рендеряться без значення:

      #{bare_decimal_renders.join("\n      ")}

      Лік: `.to_f` (або інтерполяція). ⚠️ `.round(2)` НЕ рятує, і фолбек `|| "—"`
      теж — BigDecimal істинний, тож гілка не береться. Дім → `04_04 §2`.
    MSG
  end
end
