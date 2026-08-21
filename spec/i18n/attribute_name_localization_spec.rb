# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт класу «половина повідомлення валідації, якої немає в жодному ключі».
#
# `errors.full_messages` = `"%{attribute} %{message}"`. Тобто навіть бездоганно
# перекладене повідомлення виходить напів-англійським, якщо `human_attribute_name`
# не має ключа й падає в `String#humanize`: виміряно рантаймом 2026-08-21 —
# «Photos обов'язкові для типів…», «Crypto public address не може бути…» в УСІХ
# трьох неанглійських локалях.
#
# 🔴 Чому цього не бачив жоден наявний гейт: дефект — ВІДСУТНІЙ ключ.
# `i18n-tasks missing` порівнює локаль із локаллю, а відсутнього ключа немає в
# жодній, отже парність ідеальна; лінгвістичний реєстр читає ЗНАЧЕННЯ й
# порожнечі не бачить теж. Клас той самий, що «мовчазний дефолт»: стерегти треба
# порожнечу, а «no code» не грепається.
#
# 🔒 Стеля названа, і вона тримається на КОМПОЗИЦІЇ з чужим гейтом.
#   * Перевіряється ЛИШЕ базова локаль — ціна не росте з каталогом локалей.
#     Парність по решті мов тримає `i18n-tasks missing`, і це ВИМІРЯНО, а не
#     припущено: зняття `attributes.photos` з `uk.yml` дає йому exit 1 із назвою
#     ключа, попри те що ці ключі ніхто не кличе явним `t()` (Rails резолвить їх
#     усередині `human_attribute_name`).
#   * Судиться НАЯВНІСТЬ імені, ніколи його якість. «Живе слово» машині
#     недоступне — цей бік лишається за нативним ревʼю.
#   * Периметр — курований список моделей нижче, і він НЕ дорівнює «всі моделі»:
#     сюди входять рівно ті, чиї `full_messages` доходять до людини через
#     `Views::Shared::UI::ErrorSummary`. Модель поза списком може текти далі.
RSpec.describe "validation attribute names are localized" do # rubocop:disable RSpec/DescribeClass
  # Джерело переліку — шість форм, що рендерять `ErrorSummary` з
  # `record.errors.full_messages` (firmwares · notifications · settings ·
  # maintenance · provisioning · tree_families). `provisioning` будує Tree АБО
  # Gateway, тому обидві тут.
  let(:reachable_models) do
    [ Organization, MaintenanceRecord, TreeFamily, User, BioContractFirmware, Tree, Gateway ]
  end

  # Валідовані атрибути = ті, що взагалі здатні потрапити в `full_messages`.
  # `:base` виключено свідомо: Rails друкує такі повідомлення БЕЗ префікса
  # атрибута, тож імені вони не потребують.
  def validated_attributes(model)
    model.validators.flat_map(&:attributes).uniq.reject { |a| a == :base } .sort
  end

  # Обидва доми, у порядку, у якому їх питає Rails: модель-специфічний
  # перекриває глобальний.
  def named?(model, attr)
    scoped = "activerecord.attributes.#{model.model_name.i18n_key}.#{attr}"
    global = "attributes.#{attr}"

    # ⚠️ `fallback: false` тут ІНЕРТНИЙ, і це сказано чесно: ланцюг фолбеків із
    # базової локалі веде в неї саму, тож сьогодні прапорець нічого не змінює.
    # Він стоїть як умова коректності на випадок, якщо перевірку колись
    # перецілять на НЕ-базову локаль — саме там його відсутність робить
    # `I18n.exists?` вакуумним (порожня `lv` «існує» через `en`). Тобто це не
    # несуча деталь ЦЬОГО гейта, і видавати її за несучу було б рівно тим
    # самосвідченням, яке ця сюїта й полює.
    I18n.exists?(scoped, locale: I18n.default_locale, fallback: false) ||
      I18n.exists?(global, locale: I18n.default_locale, fallback: false)
  end

  it "is a live check (each model really exposes validated attributes)" do
    expect(reachable_models).not_to be_empty

    empty = reachable_models.select { |m| validated_attributes(m).empty? }
    expect(empty).to be_empty,
      "модель без жодного валідованого атрибута не перевіряє нічого — прибери її зі списку " \
      "або з'ясуй, чому валідації зникли: #{empty.map(&:name).join(', ')}"
  end

  it "names every attribute that can reach a human through ErrorSummary" do
    unnamed = reachable_models.flat_map do |model|
      validated_attributes(model).reject { |attr| named?(model, attr) }
                                 .map { |attr| "#{model.name}##{attr}" }
    end

    expect(unnamed).to be_empty,
      "поле без імені в локалі → `full_messages` надрукує англійський `humanize` " \
      "у КОЖНІЙ мові; дім — `config/locales/attributes/*.yml` (глобально) або " \
      "`activerecord.attributes.<model>` (перекриття): #{unnamed.join(', ')}"
  end
end
