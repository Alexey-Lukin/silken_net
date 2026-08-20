# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::TelegramTransport do
  # Форма справжнього BotFather-токена; сам секрет вигаданий.
  let(:token) { "110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw11" }

  describe ".configured?" do
    it "accepts a real-shaped bot token" do
      expect(described_class.configured?({ "TELEGRAM_BOT_TOKEN" => token })).to be(true)
    end

    it "stays dead without the ENV" do
      expect(described_class.configured?({})).to be(false)
    end

    # 🔴 Та сама форматна нога, що в SMTP-предикатах: деплой-плейсхолдер не
    # порожній, тож перевірка «ENV задано» прийняла б його за живий канал.
    it "does not mistake the deploy placeholder for a configured channel" do
      expect(described_class.configured?({ "TELEGRAM_BOT_TOKEN" => "REQUIRED_SECRET_NOT_SET" }))
        .to be(false)
    end

    it "rejects strings that are not shaped like a bot token" do
      [ "", "   ", "no-colon", "abc:short", "123:" ].each do |junk|
        expect(described_class.configured?({ "TELEGRAM_BOT_TOKEN" => junk }))
          .to be(false), "#{junk.inspect} прийнято хибно"
      end
    end
  end

  describe ".send_message" do
    it "POSTs sendMessage with the chat id and text through the shared HTTP client" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(token)

      expect(Web3::HttpClient).to receive(:post).with(
        "https://api.telegram.org/bot#{token}/sendMessage",
        body: { chat_id: "42", text: "Пожежа в кластері" },
        service_name: "Telegram"
      )

      described_class.send_message(chat_id: "42", text: "Пожежа в кластері")
    end
  end
end
