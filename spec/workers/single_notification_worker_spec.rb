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

        allow(Rails.logger).to receive(:error).with(/Невідомий канал.*"sms".*доставки НЕ буде/)

        described_class.new.perform(user.id, alert.id, "sms")

        expect(Rails.logger).to have_received(:error).with(/Невідомий канал.*"sms".*доставки НЕ буде/)
      end
    end

    # [ARCH.78] Транспорт не задротований, тож приклади пінять СТАН КАНАЛУ.
    # Попередня редакція вимагала info-рядка «Надіслано»/«Доставлено» — тобто
    # цементувала твердження про доставку, якої не буває, і не могла впасти на
    # мертвому каналі. Пін на заперечення падає, щойно брехливий рядок повернуть.
    context "with push channel" do
      it "reports the push channel as unconfigured instead of claiming delivery" do
        user = create(:user, :admin, organization: organization)

        allow(Rails.logger).to receive(:warn).with(/\[Push\].*не сконфігуровано.*НЕ доставлено/)
        allow(Rails.logger).to receive(:info)

        described_class.new.perform(user.id, alert.id, "push")

        expect(Rails.logger).to have_received(:warn).with(/\[Push\].*не сконфігуровано.*НЕ доставлено/)
        expect(Rails.logger).not_to have_received(:info)
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

        allow(Rails.logger).to receive(:error).with(/Невідомий канал.*"email".*доставки НЕ буде/)

        expect {
          described_class.new.perform(user.id, alert.id, "email")
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Невідомий канал.*"email".*доставки НЕ буде/)
      end
    end

    # 🔴 [ARCH.59] Backstop-вісь: батько судить стан ОДИН раз на весь фан-аут, а ця
    # джоба виконується пізніше й лежить у черзі вдвічі довше, тож резолв між ними
    # реальний. Пін цілиться в ТРАНСПОРТ, а не в лог — інакше він був би зелений і
    # тоді, коли доставка сталася, а рядок просто не надрукувався.
    context "when the alert was resolved before this job ran" do
# ⚫ Пін ПЕРЕНЕСЕНО з telegram на push 2026-09-06 разом зі зняттям каналу
# [ARCH.60]: предмет тут — ARCH.59 (стан судиться В МИТЬ ДОСТАВКИ), а не
# конкретний транспорт, тож доказ не має гинути разом із каналом.
# ⚠️ Носій слабший за стаб транспорту: пінує ДОСЯЖНІСТЬ гілки каналу, а не
# факт відправки; посилиться в день дротування FCM [ARCH.108].
it "does not reach the channel branch" do
  user = create(:user, :admin, organization: organization)
  alert.update!(status: :resolved)
  allow(Rails.logger).to receive(:warn)

  described_class.new.perform(user.id, alert.id, "push")

  expect(Rails.logger).not_to have_received(:warn).with(/\[Push\]/)
end

it "does reach the channel branch while the alert is active" do
  user = create(:user, :admin, organization: organization)
  allow(Rails.logger).to receive(:warn)

  described_class.new.perform(user.id, alert.id, "push")

  expect(Rails.logger).to have_received(:warn).with(/\[Push\]/)
end
    end
  end
end
