# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт класу «locale-ІНВАРІАНТНІ дані, розмножені по локалях».
#
# Ендонім — власна назва мови («Українська», «Lietuvių»): вона однакова в
# будь-якому UI, бо українець шукає в перемикачі саме «Українська», а не
# «Ukrainian». Тобто це дані з нульовою локаль-залежністю, і кожна зайва копія —
# не переклад, а запрошення її «виправити».
#
# 🔴 Чому це не косметика: набір ріс як N×N. Чотири мови = 16 рядків, а
# founder-орієнтир — 150+ (`04_04 §8.1а`), тобто 22 500 однакових рядків, які
# ніхто ніколи не прочитає й кожен з яких може розійтися. Дім тепер один —
# базова локаль; решта каталогу дістає значення fallback-ланцюгом (`§12.2`),
# який саме тому й зроблено локаль-НЕЗАЛЕЖНИМ.
#
# Форма — курована tripwire (`00_06 §3`), як у `enum_label_parity_spec`, але
# вісь інша: там «джерело значень ↔ базова локаль», тут «одна копія ↔ весь
# каталог». Перевірки навмисно ітерують `I18n.available_locales`, а не
# поіменний список: п'ята мова не потребує правки цього файлу, але одразу
# потрапляє під нього.
#
# 🔒 Стеля — чого гейт НЕ бачить:
#   · Лише скоуп `locale.available`. Інша locale-інваріантна таблиця, покладена
#     в YAML (емодзі, гліфи, тікери), сюди не входить — правило для них
#     у `04_04 §12.14`, гейта на весь клас немає.
#   · Не судить ПРАВИЛЬНІСТЬ ендоніма — лише його однаковість і єдиність дому.
#     Помилку в самому слові ловить людське ревʼю, не цей файл.
RSpec.describe "locale-invariant catalogue data" do # rubocop:disable RSpec/DescribeClass
  let(:endonym_scope) { "locale.available" }
  let(:configured)    { I18n.available_locales }
  let(:base)          { I18n.default_locale }

  # Без цього «0 порушень» могло б означати «0 перевірок»: на одній локалі
  # перевірка інваріантності порівнює значення саме з собою.
  it "is a live check (more than one locale configured, base among them)" do
    expect(configured.size).to be > 1,
      "інваріантність між UI-локалями недоказова на каталозі з однієї мови"
    expect(configured).to include(base)
  end

  it "defines an endonym for every configured locale in the base locale" do
    missing = configured.reject do |code|
      I18n.exists?("#{endonym_scope}.#{code}", base, fallback: false)
    end

    expect(missing).to be_empty,
      "додано локаль без ендоніма в `#{base}` — перемикач покаже сирий код для: #{missing.join(', ')}"
  end

  # Дім рівно один. `fallback: false` тут несуче: з фолбеком «існує» будь-де.
  it "keeps the endonym table in exactly one locale file (base only)" do
    duplicated = (configured - [ base ]).flat_map do |ui|
      configured.filter_map do |code|
        "#{ui}/#{code}" if I18n.exists?("#{endonym_scope}.#{code}", ui, fallback: false)
      end
    end

    expect(duplicated).to be_empty,
      "ендонім скопійовано поза базову локаль (#{duplicated.join(', ')}) — саме звідси починається N×N-розбіг"
  end

  # Заразом пін на сам fallback-ланцюг: якщо він знову стане поіменним хешем,
  # не-базові локалі перестануть бачити таблицю і цей приклад впаде першим.
  it "resolves every endonym identically from every UI locale" do
    divergent = configured.filter_map do |code|
      seen = configured.to_h { |ui| [ ui, I18n.t("#{endonym_scope}.#{code}", locale: ui, default: nil) ] }
      "#{code}: #{seen.inspect}" if seen.values.uniq.size > 1 || seen.values.any?(&:nil?)
    end

    expect(divergent).to be_empty,
      "ендонім залежить від UI-локалі (або не резолвиться) — #{divergent.join(' · ')}"
  end
end
