# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SingleNotificationWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:alert) { create(:ews_alert, :fire, cluster: cluster) }

  describe "#perform" do
    # [ARCH.78, присуд 2026-08-20] SMS відкинуто: гілки немає, канал знято разом
    # із `users.phone_number`. Ліхтар присуду — колишній канал НЕ мовчить, а
    # падає в гучну unknown-гілку (застарілий продюсер стане видимим одразу).
    context "with the retired sms channel" do
      it "routes into the loud unknown-channel branch instead of a silent stub" do
        user = create(:user, :forester, organization: organization)

        expect(Rails.logger).to receive(:error).with(/Невідомий канал.*"sms".*доставки НЕ буде/)

        described_class.new.perform(user.id, alert.id, "sms")
      end
    end

    # [ARCH.78] Транспорт не задротований, тож приклади пінять СТАН КАНАЛУ.
    # Попередня редакція вимагала info-рядка «Надіслано»/«Доставлено» — тобто
    # цементувала твердження про доставку, якої не буває, і не могла впасти на
    # мертвому каналі. Пін на заперечення падає, щойно брехливий рядок повернуть.
    context "with push channel" do
      it "reports the push channel as unconfigured instead of claiming delivery" do
        user = create(:user, :admin, organization: organization)

        expect(Rails.logger).to receive(:warn).with(/\[Push\].*не сконфігуровано.*НЕ доставлено/)
        expect(Rails.logger).not_to receive(:info)

        described_class.new.perform(user.id, alert.id, "push")
      end
    end

    # [ARCH.60] Telegram — перший живий не-поштовий канал. Транспорт стабиться
    # на юніт-межі (HTTP-половина має власну спеку) — тут пінується диспетчер:
    # кому, що і в якій мові він передає.
    context "with telegram channel" do
      it "delivers through the transport in the recipient's locale" do
        user = create(:user, :forester, organization: organization,
                      telegram_chat_id: "123456789", locale: "uk")
        allow(Notifications::TelegramTransport).to receive(:configured?).and_return(true)
        delivered = nil
        allow(Notifications::TelegramTransport).to receive(:send_message) do |chat_id:, text:|
          delivered = { chat_id: chat_id, text: text }
        end

        described_class.new.perform(user.id, alert.id, "telegram")

        uk_text = I18n.with_locale(:uk) { alert.message }
        # Ліхтар: якби uk-рендер збігався з базовим, пін локалі був би вакуумним.
        expect(uk_text).not_to eq(I18n.with_locale(I18n.default_locale) { alert.message })
        expect(delivered).to eq({ chat_id: "123456789", text: uk_text })
      end

      it "stays silent for users who did not opt in with a chat id" do
        user = create(:user, :forester, organization: organization, telegram_chat_id: nil)
        expect(Notifications::TelegramTransport).not_to receive(:send_message)
        expect(Rails.logger).not_to receive(:warn).with(/\[Telegram\]/)

        described_class.new.perform(user.id, alert.id, "telegram")
      end

      it "reports the channel as unconfigured instead of claiming delivery" do
        user = create(:user, :forester, organization: organization, telegram_chat_id: "123456789")
        allow(Notifications::TelegramTransport).to receive(:configured?).and_return(false)

        expect(Notifications::TelegramTransport).not_to receive(:send_message)
        expect(Rails.logger).to receive(:warn).with(/\[Telegram\].*не сконфігуровано.*НЕ доставлено/)

        described_class.new.perform(user.id, alert.id, "telegram")
      end

      it "lets transport errors escape so Sidekiq retries the delivery" do
        user = create(:user, :forester, organization: organization, telegram_chat_id: "123456789")
        allow(Notifications::TelegramTransport).to receive(:configured?).and_return(true)
        allow(Notifications::TelegramTransport).to receive(:send_message)
          .and_raise(Web3::HttpClient::RequestError, "Telegram API returned 502")

        expect {
          described_class.new.perform(user.id, alert.id, "telegram")
        }.to raise_error(Web3::HttpClient::RequestError)
      end
    end

    it "returns nil when user not found" do
      expect(described_class.new.perform(-1, alert.id, "push")).to be_nil
    end

    it "returns nil when alert not found" do
      user = create(:user, organization: organization)

      expect(described_class.new.perform(user.id, -1, "push")).to be_nil
    end

    it "returns nil when both not found" do
      expect(described_class.new.perform(-1, -1, "push")).to be_nil
    end

    # [ARCH.78] Раніше цей приклад пінив ТИШУ як бажану поведінку («does nothing»),
    # тобто фіксував відсутність else-гілки як контракт. Невідомий канал на тракті
    # критичних тривог мусить бути гучним: тиша тут невідрізненна від доставки.
    context "with unknown channel" do
      it "logs the unknown channel loudly instead of dying silently" do
        user = create(:user, :admin, organization: organization)

        expect(Rails.logger).to receive(:error).with(/Невідомий канал.*"email".*доставки НЕ буде/)

        expect {
          described_class.new.perform(user.id, alert.id, "email")
        }.not_to raise_error
      end
    end

    # 🔴 [ARCH.59] Backstop-вісь: батько судить стан ОДИН раз на весь фан-аут, а ця
    # джоба виконується пізніше й лежить у черзі вдвічі довше, тож резолв між ними
    # реальний. Пін цілиться в ТРАНСПОРТ, а не в лог — інакше він був би зелений і
    # тоді, коли доставка сталася, а рядок просто не надрукувався.
    context "when the alert was resolved before this job ran" do
      it "does not touch the transport" do
        user = create(:user, :admin, organization: organization, telegram_chat_id: "123")
        allow(Notifications::TelegramTransport).to receive(:configured?).and_return(true)
        allow(Notifications::TelegramTransport).to receive(:send_message)
        alert.update!(status: :resolved)

        described_class.new.perform(user.id, alert.id, "telegram")

        expect(Notifications::TelegramTransport).not_to have_received(:send_message)
      end

      it "does touch the transport while the alert is active" do
        user = create(:user, :admin, organization: organization, telegram_chat_id: "123")
        allow(Notifications::TelegramTransport).to receive(:configured?).and_return(true)
        allow(Notifications::TelegramTransport).to receive(:send_message)

        described_class.new.perform(user.id, alert.id, "telegram")

        expect(Notifications::TelegramTransport).to have_received(:send_message)
      end
    end
  end
end
