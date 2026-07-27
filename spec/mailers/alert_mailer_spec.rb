# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertMailer, type: :mailer do
  describe "#critical_notification" do
    subject(:mail) { described_class.with(alert: alert).critical_notification }

    let(:organization) { create(:organization, billing_email: "ops@forest.ua") }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:alert) { create(:ews_alert, :fire, cluster: cluster) }

    it "sends to the organization billing email" do
      expect(mail.to).to eq([ "ops@forest.ua" ])
    end

    # Літерал навмисний. Раніше тут стояло `alert.alert_type.humanize` — тобто
    # спека рахувала очікування ТИМ САМИМ методом, що й код, і тому не бачила,
    # що тема листа взагалі не ходить через локаль. Пін доводить, що мітка
    # приходить із `alerts.types.*`, а не з `humanize`-фолбеку.
    it "includes the localized alert-type label and cluster name in the subject" do
      expect(mail.subject).to include("Fire Detected")
      expect(mail.subject).not_to include("Fire detected")
      expect(mail.subject).to include(cluster.name)
    end

    it "includes the S-NET prefix in the subject" do
      expect(mail.subject).to include("[S-NET]")
    end

    it "renders the body" do
      expect(mail.body.encoded).to be_present
    end

    # [I18N.1] Тут локаль ОРГАНІЗАЦІЇ, а не користувача: лист іде на
    # `billing_email`, за яким може не стояти жоден User-запис. Це не дублювання
    # `users.locale` — це інший адресат.
    describe "recipient locale" do
      it "falls back to the default locale when the organization has no preference" do
        organization.update!(locale: nil)

        expect(mail.subject).to include("Critical alert")
        expect(mail.body.encoded).to include("CRITICAL ALERT")
      end

      # Заразом доводить, що локаль дістає й `alert_title`: він резолвиться через
      # `I18n.t` у момент рендеру, тож до цієї роботи виходив АНГЛІЙСЬКИМ усередині
      # українського тіла — двомовний лист, у якому симптом видно лише цілком.
      it "renders subject AND the alert-type label in the organization's locale" do
        organization.update!(locale: "uk")

        expect(mail.subject).to include("Критична тривога")
        expect(mail.subject).to include("Виявлено пожежу")
        expect(mail.body.encoded).to include("КРИТИЧНА ТРИВОГА")
      end
    end
  end
end
