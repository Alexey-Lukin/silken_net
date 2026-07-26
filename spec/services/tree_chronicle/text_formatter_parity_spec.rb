# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт осі, якої CI НЕ бачить. `i18n-tasks missing` звіряє локаль з локаллю —
# enum може вирости, а YAML лишитись порожнім, і гейт буде зелений (саме так
# `alert_type` тихо доріс до 14 значень, поки формат знав 9). Тут перевіряється
# рівно та вісь, що лишається: модель ↔ базова локаль, в обидва боки.
#
# ⚠️ `fallback: false` обов'язковий. `config/application.rb` вмикає fallbacks у
# ВСІХ середовищах, а `I18n.exists?` за замовчуванням іде по ланцюгу — без цього
# прапорця порожня `lv` «існує» через `en`, і перевірка стає вакуумною.
RSpec.describe TreeChronicle::TextFormatter do
  describe "enum↔locale parity for EwsAlert#alert_type" do
    let(:scope) { described_class::ALERT_TYPE_SCOPE }

    it "has a base-locale label for every enum value" do
      missing = EwsAlert.alert_types.keys.reject do |type|
        I18n.exists?("#{scope}.#{type}", I18n.default_locale, fallback: false)
      end

      expect(missing).to be_empty, "no `#{scope}.<type>` label for: #{missing.join(', ')}"
    end

    # Зворотний бік «parity» — інакше слово в назві обіцяє дві перевірки, а
    # реалізована одна (класична сліпота гейта на власний контракт).
    it "has no orphaned label for a value the enum no longer defines" do
      declared = I18n.t(scope, locale: I18n.default_locale).keys.map(&:to_s)
      orphans  = declared - EwsAlert.alert_types.keys

      expect(orphans).to be_empty, "label without an enum value: #{orphans.join(', ')}"
    end

    it "has an icon for every enum value" do
      missing = EwsAlert.alert_types.keys - described_class::ALERT_ICONS.keys

      expect(missing).to be_empty, "no icon for: #{missing.join(', ')}"
    end

    # Літерал навмисний: обидві сторони, зібрані з тієї самої константи, дали б
    # вакуумну рівність (typo в scope → humanize з обох боків → зелено). Пін
    # доводить, що TextFormatter реально дістає рядок із YAML і що локаль тече.
    it "resolves through the locale file, not the humanize fallback" do
      alert = EwsAlert.new(alert_type: :firmware_canary_trip)

      I18n.with_locale(:uk) do
        expect(described_class.alert_title(alert)).to eq("Спрацювала канарка прошивки")
      end
    end
  end
end
