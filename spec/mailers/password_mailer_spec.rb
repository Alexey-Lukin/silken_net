# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordMailer, type: :mailer do
  describe "#reset_instructions" do
    subject(:mail) { described_class.with(user: user).reset_instructions }

    let(:user) { create(:user) }

    it "sends to the user email address" do
      expect(mail.to).to eq([ user.email_address ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to be_present
    end

    # [I18N.1] Тут раніше стояв пін на українську тему листа — і він проходив,
    # бо пошта БУЛА мономовною незалежно від адресата. Тобто спека фіксувала
    # рівно той дефект, який ми лагодимо. Тепер вісь інша: мова листа = мова
    # ОТРИМУВАЧА, а не мова, якою написали шаблон.
    describe "recipient locale" do
      it "falls back to the default locale when the user has no preference" do
        user.update!(locale: nil)

        expect(mail.subject).to include("Password reset")
        expect(mail.body.encoded).to include("Hello")
      end

      it "renders subject AND body in the recipient's stored locale" do
        user.update!(locale: "uk")

        expect(mail.subject).to include("Скидання пароля")
        expect(mail.body.encoded).to include("Вітаємо")
      end

      # Локаль могла пережити зняття мови з каталогу. `I18n.with_locale` кинув би
      # `InvalidLocale` і вбив би доставку — лист не сміє загинути через мітку мови.
      it "degrades to the default locale instead of raising on an unsupported value" do
        user.update_column(:locale, "zz-not-a-locale")

        expect { mail.subject }.not_to raise_error
        expect(mail.subject).to include("Password reset")
      end
    end

    # Термін дії називається словами в тілі листа, а виставляється константою
    # моделі. Поки це були два незалежні літерали, вони могли розійтися мовчки.
    it "states the link lifetime from the same source that issues the token" do
      minutes = (User::PASSWORD_RESET_TTL / 60).to_i

      expect(mail.body.encoded).to include(minutes.to_s)
    end
  end
end
