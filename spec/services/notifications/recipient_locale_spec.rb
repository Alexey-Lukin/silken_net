# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.1] Один дім локалі отримувача для всіх Sidekiq-каналів, що рендерять текст.
# ⚫ Мешканець сьогодні ОДИН — сама пошта: Telegram знято ⚖️ 2026-09-06 [ARCH.60].
# Дім лишається спільним свідомо: він був відповіддю на «канал другий зʼявиться»,
# а не наслідком того, що їх стало два.
RSpec.describe Notifications::RecipientLocale do
  it "returns the persisted locale when it is in the catalogue" do
    expect(described_class.for(User.new(locale: "uk"))).to eq(:uk)
  end

  it "degrades to the default locale on NULL — «не обрано» не сміє вбити доставку" do
    expect(described_class.for(User.new(locale: nil))).to eq(I18n.default_locale)
  end

  # Значення могло пережити зняття локалі з каталогу; `I18n.with_locale` на
  # невідомій кидає `InvalidLocale`, тож фолбек тут — про живучість доставки.
  it "degrades to the default locale on a value no longer in the catalogue" do
    expect(described_class.for(User.new(locale: "tlh"))).to eq(I18n.default_locale)
  end

  it "answers the default for records without a locale at all" do
    expect(described_class.for(nil)).to eq(I18n.default_locale)
  end
end
