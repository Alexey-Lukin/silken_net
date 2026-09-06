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
      # [ARCH.78] :sms у переліку немає — канал відкинуто присудом 2026-08-20.
      # [ARCH.60] :telegram теж — зрізано ⚖️ 2026-09-06 при нулі споживачів.
      expect(described_class::ALL).to contain_exactly(:email, :push)

      described_class::ALL.each do |channel|
        expect(described_class.available?(channel)).to be(false), "#{channel} оголошено живим"
      end
      expect(described_class.available).to be_empty
    end

    it "не вигадує каналів, яких не оголошено" do
      expect(described_class.available?(:carrier_pigeon)).to be(false)
    end
  end

  # [ARCH.60] Відправник — половина конʼюнкції вище, і саме та, що резолвиться
  # ТУТ, а не в мейлері: `ApplicationMailer.default from:` лише читає це.
  describe ".configured_sender" do
    it "бере ENV, коли той заданий" do
      expect(described_class.configured_sender({ "MAIL_FROM" => "alerts@silkennet.com" }))
        .to eq("alerts@silkennet.com")
    end

    it "падає назад у сентинел, а НЕ у правдоподібну адресу" do
      # Несуче: фолбек мусить лишатись тим значенням, яке `sender_configured?`
      # читає як «не налаштовано». Правдоподібний дефолт зробив би канал
      # оголошено-живим при мертвому транспорті — рівно дефект, який лікуємо.
      [ {}, { "MAIL_FROM" => "" }, { "MAIL_FROM" => "   " } ].each do |env|
        expect(described_class.configured_sender(env)).to eq(described_class::SCAFFOLD_SENDER)
      end
    end

    it "віддає РЯДОК, бо `Proc` тихо зламав би предикат" do
      expect(described_class.configured_sender({ "MAIL_FROM" => "a@b.co" })).to be_a(String)
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

    it "живий канал доводиться ТИМ САМИМ предикатом, що ним боот-гард пускає прод" do
      # [ARCH.60] `config/initializers/mail_transport_check.rb` питає рівно це.
      # Пін тримає зчеплення: розділити відповіді екрана й гарда означало б
      # дозволити платформі стартувати, вважаючи пошту живою, і малювати її мертвою.
      configure(from: "alerts@silkennet.com", smtp_address: "smtp.postmarkapp.com")

      expect(described_class.sender_configured?).to be(true)
      expect(described_class.smtp_host_configured?).to be(true)
    end

    # 🔴 Найдорожчий напрямок: деплой-файли несуть `REQUIRED_SECRET_NOT_SET` як видиме
    # нагадування «сюди підставити». Він не порожній і не сентинел — тобто без форматної
    # ноги предикат прийняв би його за справжнє значення, і плейсхолдер, вигаданий гучно
    # падати, ТИХО проходив би boot-гард.
    it "не приймає деплой-плейсхолдер за налаштований канал" do
      configure(from: "REQUIRED_SECRET_NOT_SET", smtp_address: "REQUIRED_SECRET_NOT_SET")

      expect(described_class.sender_configured?).to be(false)
      expect(described_class.smtp_host_configured?).to be(false)
      expect(described_class.available?(:email)).to be(false)
    end

    it "приймає форми, які справжній деплой реально має" do
      # Ліхтар проти протилежного дрейфу — форматна нога не сміє відкидати живі значення.
      [ "smtp.postmarkapp.com", "email-smtp.eu-west-1.amazonaws.com", "10.0.0.5", "mailrelay" ]
        .each do |host|
          configure(from: "SilkenNet <alerts@silkennet.com>", smtp_address: host)
          expect(described_class.available?(:email)).to be(true), "#{host} відкинуто хибно"
        end
    end

    it "не тягне за собою решту каналів — у них власне оголошення" do
      configure(from: "alerts@silkennet.com", smtp_address: "smtp.postmarkapp.com")

      expect(described_class.available?(:push)).to be(false)
      # ⚫ Гілки `:telegram` більше немає — канал зрізано ⚖️ 2026-09-06 [ARCH.60];
      # невідомий символ падає в `else → false`, що й пінує приклад нижче.
      expect(described_class.available?(:telegram)).to be(false)
    end
  end
end
