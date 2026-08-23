# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Носій інваріанта «uniqueness-валідація має DB-індекс за спиною» [OPS.33, дзеркало ARCH.56].
#
# 🔴 Чому окремий гейт, хоча коп існує: `Rails/UniqueValidationWithoutIndex` читає ВИКЛЮЧНО
# `db/schema.rb`, а ми на `schema_format = :sql` — файлу не існує, тож коп мовчки не дивиться
# нікуди. Його нуль вимірює ІНСТРУМЕНТ, не дерево (клас «пін на порожній множині»), і саме
# тому вмикання копа за приписом дало б зелене під іменем, що обіцяє захист.
#
# 🔑 ЧОГО КОШТУЄ ПРОПУСК. Валідація Rails — це `SELECT` перед `INSERT`, тобто вікно гонки:
# два одночасні запити обидва бачать «вільно» й обидва пишуть. Дубль, який застосунок вважає
# неможливим, живе далі в даних — і виявляється не помилкою, а розходженням чисел.
# Виміряно 2026-08-23: 19 валідаторів, БЕЗ індексу — нуль. Гейт народжується зеленим і
# стереже наступний `validates … uniqueness:`, доданий без міграції.
#
# 🔒 СТЕЛЯ — що цей гейт НЕ бачить:
#   1. **Відповідність УМОВ.** Судиться лише набір КОЛОНОК. Умовна валідація, підперта
#      частковим індексом (`EwsAlert`: `if: status_active? && tree_id.present?` ⟷
#      `WHERE status = 0 AND tree_id IS NOT NULL`), приймається без звірки самих умов —
#      сьогодні ця пара коректна, перевірено руками, але гейт цього довести не може.
#   2. **Часткові індекси по NULL** (`WHERE col IS NOT NULL`) приймаються свідомо: у Postgres
#      звичайний unique index і так пускає довільну кількість NULL, тож для не-NULL випадку
#      гарантія тотожна, а індекс лише менший.
#   3. **`case_sensitive: false`** потребував би функціонального індексу на `lower(col)`.
#      У дереві таких валідацій нуль (виміряно); зʼявиться — гейт треба ВЧИТИ, не послаблювати.
#   4. **Саморобну перевірку унікальності** у власному валідаторі або в сервісі — тут теж нуль.
#   5. **Живу БД.** Джерело — `db/structure.sql`, тобто наша ОГОЛОШЕНА схема. Розходження
#      декларації з продом — предмет міграційної дисципліни, не цього гейта.
RSpec.describe "uniqueness-валідація ⟷ унікальний індекс", type: :model do
  # Набори колонок, на які в `structure.sql` є унікальна гарантія: `CREATE UNIQUE INDEX`
  # (включно з частковими) + `PRIMARY KEY`/`UNIQUE`-констрейнти.
  def unique_column_sets
    sql = File.read(Rails.root.join("db/structure.sql"))
    sets = Hash.new { |h, k| h[k] = [] }
    sql.scan(/CREATE UNIQUE INDEX \S+ ON (?:\w+\.)?(\w+) USING \w+ \(([^)]+)\)/) do |tbl, cols|
      sets[tbl] << cols.split(",").map { |c| c.strip.sub(/\s+\w+\z/, "").delete('"') }.sort
    end
    sql.scan(/ALTER TABLE ONLY (?:\w+\.)?(\w+)\s*\n\s*ADD CONSTRAINT \S+ (?:PRIMARY KEY|UNIQUE) \(([^)]+)\)/) do |tbl, cols|
      sets[tbl] << cols.split(",").map { |c| c.strip.delete('"') }.sort
    end
    sets
  end

  it "кожна uniqueness-валідація підперта унікальним індексом у db/structure.sql" do
    Rails.application.eager_load!
    sets = unique_column_sets
    expect(sets.size).to be > 10, "structure.sql не розпарсився — гейт судив би порожнечу"

    checked = 0
    missing = []
    ActiveRecord::Base.descendants.each do |model|
      next if model.abstract_class? || !model.table_exists?

      model.validators.grep(ActiveRecord::Validations::UniquenessValidator).each do |v|
        scope = Array(v.options[:scope]).map(&:to_s)
        v.attributes.each do |attr|
          want = ([ attr.to_s ] + scope).sort
          checked += 1
          next if sets[model.table_name].include?(want)

          missing << "#{model.name}: `validates :#{attr}, uniqueness:#{scope.empty? ? '' : " scope #{scope.inspect}"}` " \
                     "— у `#{model.table_name}` немає унікального індексу на (#{want.join(', ')})"
        end
      end
    end

    expect(checked).to be_positive, "жодного uniqueness-валідатора не знайдено — інтроспекція мовчить, а не дерево чисте"
    expect(missing).to be_empty, lambda {
      "Валідація Rails — це SELECT перед INSERT, тобто вікно гонки: два одночасні запити " \
        "обидва бачать «вільно». Без індексу дубль, який застосунок вважає неможливим, " \
        "осідає в даних мовчки [ARCH.56].\n#{missing.join("\n")}"
    }
  end
end
