# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 `code_tracker_id_check` розколює цитований токен на кінці ДІАПАЗОНУ
# (`E.20-E.34`) — і не сміє розколювати дефіс УСЕРЕДИНІ префікса родини
# (`DOC-T.62`).
#
# Механізм. До 2026-08-09 розкол мав лише lookahead, тож `DOC-T.62` ставало
# `DOC` + `T.62`; жоден із фрагментів не є родиною, `families.include?` відкидав
# обидва, і цитата не перевірялась ВЗАГАЛІ. Виміряно на день фіксу: 57 із 494
# ID трекера — `DOC-T.*`, а цитат на них у деревах цього гейта — 201, тобто вся
# SSOT-tooling родина була невидима. Мутація в обидва боки: фантом `DOC-T.999`
# проходив зеленим, тоді як `SEC.999`/`ARCH.999`/`UI.999` червонили.
#
# Це той САМИЙ клас, що шапка `TOKEN_RE` записує як уже полагоджений для
# `SLASH-1`: його вилікували там, де токен РОЗПІЗНАЄТЬСЯ, і лишили там, де його
# РОЗКОЛЮЮТЬ. Half-fix, у якому здорова половина й ховає хвору — тому пін
# стереже саме розкол, окремо від розпізнавання.
#
# 🔒 Чому спека читає регекс із ДЖЕРЕЛА, а не тримає власну копію: копія
# зробила б цей файл другим домом форми, і тоді послаблення в скрипті лишилось
# би зеленим тут (guard-craft — «expectation must not re-run the logic under
# test»). Витяг із джерела означає, що спека червоніє і на послабленні форми, і
# на її зникненні.
module TrackerIdRangeSplit
  SOURCE = Rails.root.join("scripts/code_tracker_id_check.rb")

  # Рядок, що виконує розкол діапазону. Анкер — присвоєння `parts = tok.split(`,
  # бо саме воно є предметом; літерал регексу береться як є.
  def self.range_split_regexp
    line = SOURCE.read[/^\s*parts\s*=\s*tok\.split\((\/.*\/)\)\s*$/, 1]
    raise "не знайдено рядок розколу діапазону у #{SOURCE}" if line.nil?

    Regexp.new(line[%r{\A/(.*)/\z}m, 1])
  end
end

RSpec.describe TrackerIdRangeSplit, type: :quality do
  subject(:re) { described_class.range_split_regexp }

  # Кожен кейс = вхідний токен → як він МУСИТЬ розколотись.
  {
    # діапазони — розколюються
    "E.20-E.34" => %w[E.20 E.34],
    "ARCH.12-ARCH.13" => %w[ARCH.12 ARCH.13],
    "E.20-E.34-E.40" => %w[E.20 E.34 E.40],
    "DOC-T.62-DOC-T.63" => %w[DOC-T.62 DOC-T.63], # діапазон ДЕФІСНИХ родин
    "DOC-T.20-DOC-T.34" => %w[DOC-T.20 DOC-T.34],
    "S1.1-S2.3" => %w[S1.1 S2.3],
    # 🔴 Правий кінець діапазону може бути ДЕФІС-ЧИСЛОВОЮ родиною (`SLASH-1`),
    # тож лукахед мусить приймати `[.\-]\d`, як `families`/`TOKEN_RE`, а не лише
    # `\.\d`. З вужчою формою токен лишається цілим, родина `E` все одно
    # матчиться, і гейт репортує ХИБНИЙ фантом — при тому, що обидва кінці
    # живі в трекері. Цей кейс — єдине, що розводить дві форми.
    "E.20-SLASH-1" => %w[E.20 SLASH-1],
    "SLASH-1-SLASH-2" => %w[SLASH-1 SLASH-2],
    # дефіс усередині префікса — НЕ розколюється
    "DOC-T.62" => %w[DOC-T.62],
    "DOC-T.5" => %w[DOC-T.5],
    "SEC.25" => %w[SEC.25],
    "SLASH-1" => %w[SLASH-1],
    "PUMA-IPV6-1" => %w[PUMA-IPV6-1],
    "SE050-MIGRATION" => %w[SE050-MIGRATION],
    # фасети й фікстурні рядки — цілі (саме заради них шапка вимагає dotted)
    "UI.2-S" => %w[UI.2-S],
    "ARCH.35-Q2Q" => %w[ARCH.35-Q2Q],
    "TEST-DEVICE-001" => %w[TEST-DEVICE-001]
  }.each do |token, expected|
    it "розколює #{token.inspect} у #{expected.inspect}" do
      expect(token.split(re)).to eq(expected)
    end
  end

  # 🔦 Ліхтар на непорожність: без нього все вище лишається зеленим, якщо
  # витягач мовчки поверне регекс, що не матчить нічого.
  it "витягнутий регекс справді розколює хоч один діапазон" do
    expect("E.20-E.34".split(re).size).to eq(2)
  end

  it "розкол лишається чутливим до ЗАВЕРШЕНОГО id зліва (lookbehind на місці)" do
    expect(re.source).to include('(?<=')
  end

  # 🔦 Другий ліхтар — на ПРЕДМЕТ, не на форму. Уся батарея вище лишилась би
  # зеленою, якби дефісні родини зникли з трекера: вона стерегла б порожнечу.
  it "дефісна родина в трекері непорожня — інакше цей гейт стереже ніщо" do
    ids = Tracker::Dashboard.all_item_ids(File.read(Tracker::Dashboard::DEFAULT_PATH))
    hyphenated = ids.select { |id| id.match?(/\A[A-Z][A-Za-z0-9]*-[A-Z]/) }

    expect(hyphenated).not_to be_empty
    expect(hyphenated).to include(a_string_matching(/\ADOC-T\.\d+\z/))
  end
end
