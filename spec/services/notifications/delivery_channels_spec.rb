# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.10] Носій оголошення про транспорти. Стереже дві протилежні напрямки
# дрейфу: канал, оголошений живим при мертвому транспорті, і — дорожче —
# транспорт, який задротували, а екран далі каже «не налаштовано».
RSpec.describe Notifications::DeliveryChannels do
  describe ".available?" do
    it "сьогодні не має ЖОДНОГО живого каналу" do
      # Ліхтар: без нього приклад був би зелений і на порожньому переліку.
      expect(described_class::ALL).to contain_exactly(:email, :sms, :telegram, :push)

      described_class::ALL.each do |channel|
        expect(described_class.available?(channel)).to be(false), "#{channel} оголошено живим"
      end
      expect(described_class.available).to be_empty
    end

    it "не вигадує каналів, яких не оголошено" do
      expect(described_class.available?(:carrier_pigeon)).to be(false)
    end
  end

  # Пошта — єдиний канал із машинно-спостережуваним транспортом, тож і єдиний,
  # чий перехід у «живий» можна довести без правки цього файлу.
  describe ".available?(:email)" do
    def configure(from:, smtp_address:)
      allow(ApplicationMailer).to receive(:default).and_return({ from: from })
      allow(ActionMailer::Base).to receive(:smtp_settings).and_return({ address: smtp_address })
    end

    it "оживає, коли задротовано ОБИДВА — і відправника, і транспорт" do
      configure(from: "alerts@silkennet.com", smtp_address: "smtp.postmarkapp.com")

      expect(described_class.available?(:email)).to be(true)
      expect(described_class.available).to include(:email)
    end

    # Конʼюнкція несуча: кожна половина окремо лишає канал мертвим, і саме тому
    # вона не «про всяк випадок» — перша нога ARCH.60 везе обидві разом.
    it "лишається мертвою на справжньому відправнику й незайманому SMTP" do
      configure(from: "alerts@silkennet.com", smtp_address: "localhost")

      expect(described_class.available?(:email)).to be(false)
    end

    it "лишається мертвою на справжньому SMTP і скаффолд-відправнику" do
      configure(from: "from@example.com", smtp_address: "smtp.postmarkapp.com")

      expect(described_class.available?(:email)).to be(false)
    end

    it "не тягне за собою решту каналів — у них власне оголошення" do
      configure(from: "alerts@silkennet.com", smtp_address: "smtp.postmarkapp.com")

      expect(described_class.available?(:sms)).to be(false)
      expect(described_class.available?(:telegram)).to be(false)
      expect(described_class.available?(:push)).to be(false)
    end
  end
end
