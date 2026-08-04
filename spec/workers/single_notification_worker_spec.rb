# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SingleNotificationWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:alert) { create(:ews_alert, :fire, cluster: cluster) }

  describe "#perform" do
    # [ARCH.78] Транспорт не задротований, тож приклади пінять СТАН КАНАЛУ.
    # Попередня редакція вимагала info-рядка «Надіслано»/«Доставлено» — тобто
    # цементувала твердження про доставку, якої не буває, і не могла впасти на
    # мертвому каналі. Пін на заперечення падає, щойно брехливий рядок повернуть.
    context "with SMS channel" do
      it "reports the SMS channel as unconfigured instead of claiming delivery" do
        user = create(:user, :forester, organization: organization, phone_number: "+380501234567")

        expect(Rails.logger).to receive(:warn).with(/\[SMS\].*не сконфігуровано.*НЕ надіслано/)
        expect(Rails.logger).not_to receive(:info)

        described_class.new.perform(user.id, alert.id, "sms")
      end

      it "skips SMS when user has no phone number" do
        user = create(:user, :forester, organization: organization, phone_number: nil)

        expect(Rails.logger).not_to receive(:warn).with(/\[SMS\]/)

        described_class.new.perform(user.id, alert.id, "sms")
      end
    end

    context "with push channel" do
      it "reports the push channel as unconfigured instead of claiming delivery" do
        user = create(:user, :admin, organization: organization)

        expect(Rails.logger).to receive(:warn).with(/\[Push\].*не сконфігуровано.*НЕ доставлено/)
        expect(Rails.logger).not_to receive(:info)

        described_class.new.perform(user.id, alert.id, "push")
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
      expect(described_class.new.perform(-1, -1, "sms")).to be_nil
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
  end
end
