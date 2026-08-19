# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.18] Гейт ПОВНОТИ PII-реєстру — `04_01 §11`.
#
# 🔴 Навіщо. Три обовʼязки читають ОДИН перелік персональних колонок і доти виводили
# його кожен по-своєму: RoPA Art.30, DSAR-експорт Art.15/20 і retention-TTL. Розсипаний
# по тридцяти таблицях, такий перелік не має способу бути ПОВНИМ — а саме повнота тут
# і є вимогою: пропущена колонка не віддається субʼєкту, не стирається й не має строку,
# і жодна з трьох відсутностей не червоніє.
#
# 🧱 ГЕЙТ СУДИТЬ НАЯВНІСТЬ РЯДКА, НІКОЛИ ЙОГО ПРАВИЛЬНІСТЬ. Класифікація — декларація
# людини (`gateways.ip_address` це egress ПРИСТРОЮ, а `biomass_passport_tx_hash`
# збігається на слові «passport» і є TX-хешем Puro). Машина може перевірити лише те,
# що про колонку ВЗАГАЛІ ухвалено рішення.
#
# 🔒 Стелі названо, інакше зелений читається ширше:
#   1. Джерело — `db/structure.sql`, тобто КОЛОНКИ. Персональні дані, що живуть у
#      JSONB (`reasoning`, `metadata`, `prediction_data`) або приходять із зовнішнього
#      API, цим приладом не видно за побудовою — і схема сліпа до `store_accessor`
#      так само (`04_06 §B.2` BP #14).
#   2. Патерн ловить ІМЕНА, а не зміст: колонка `notes`, у яку оператор впише телефон,
#      пройде мовчки. Це не усувна вада — лише названа.
#   3. Партиції (`*_y2026m01`) згортаються в батьківську таблицю: вони її копії, і
#      судити їх окремо означало б вимагати тридцять однакових рядків реєстру.
RSpec.describe "[SEC.18] PII-реєстр повний", type: :model do
  let(:doc_path)    { Rails.root.join("docs/04_01_Data_Models_and_Entities.md") }
  let(:schema_path) { Rails.root.join("db/structure.sql") }

  # Іменні ознаки персональних даних. Розширювати ЛИШЕ разом із рядком реєстру —
  # інакше гейт червоніє на колонці, про яку рішення ще не ухвалено.
  let(:pii_pattern) do
    /email|phone|first_name|last_name|full_name|telegram|push_token|ip_address|
     user_agent|recovery_codes|passport|birth|national_id|passw/xi
  end

  # Колонки, що збігаються з патерном і живуть у схемі — згруповані за БАТЬКІВСЬКОЮ
  # таблицею (партиція успадковує рядок реєстру своєї таблиці).
  let(:schema_hits) do
    sql = schema_path.read
    sql.scan(/CREATE TABLE public\.(\w+) \((.*?)\n\);/m).each_with_object(Hash.new { |h, k| h[k] = [] }) do |(table, body), acc|
      parent = table.sub(/_y\d{4}m\d{2}\z/, "")
      body.each_line do |line|
        col = line.strip.split(/\s+/).first.to_s
        next if col.empty? || line.strip.start_with?("CONSTRAINT")
        next unless col.match?(pii_pattern)

        acc[parent] << col unless acc[parent].include?(col)
      end
    end
  end

  # Реєстр — рядки таблиці §11, де перша комірка несе `` `таблиця` `` і колонки.
  let(:registered) do
    section = doc_path.read[/### PII-реєстр.*?(?=\n## )/m].to_s
    raise "секцію PII-реєстру не знайдено — гейт міряв би порожнечу" if section.empty?

    section
  end

  it "ліхтар: схема справді містить PII-подібні колонки" do
    expect(schema_hits.size).to be >= 5,
                                "знайдено #{schema_hits.size} таблиць — патерн або шлях до схеми обвалились"
  end

  it "ліхтар: секція реєстру непорожня й має рядки таблиці" do
    expect(registered.scan(/^\|/).size).to be >= 8,
                                           "реєстр несе #{registered.scan(/^\|/).size} рядків — секція виродилась"
  end

  it "кожна PII-подібна колонка схеми КЛАСИФІКОВАНА в реєстрі" do
    missing = schema_hits.flat_map do |table, cols|
      cols.filter_map do |col|
        # Колонка вважається класифікованою, якщо реєстр згадує і таблицю, і саму
        # колонку. Пара, а не одне з двох: `ip_address` живе у ТРЬОХ таблицях із
        # РІЗНИМИ класами, тож самої назви колонки замало.
        next if registered.include?("`#{table}`") && registered.include?(col)

        "#{table}.#{col}"
      end
    end

    expect(missing).to be_empty, <<~MSG
      Колонка з ознаками персональних даних не класифікована в `04_01 §11`:
        #{missing.join("\n  ")}

      Реєстр годує ТРИ обовʼязки одразу — RoPA Art.30, DSAR-експорт і retention-TTL,
      — і пропущена колонка не віддається субʼєкту, не стирається й не має строку,
      причому жодна з трьох відсутностей не червоніє сама. Додай рядок із ПІДСТАВОЮ
      (клас може бути й «НЕ PII» — гейт судить наявність рішення, не його зміст).
    MSG
  end
end
