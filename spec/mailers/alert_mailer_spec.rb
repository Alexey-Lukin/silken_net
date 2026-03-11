# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertMailer, type: :mailer do
  describe "#critical_notification" do
    let(:organization) { create(:organization, billing_email: "ops@forest.ua") }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:alert) { create(:ews_alert, :fire, cluster: cluster) }

    subject(:mail) { described_class.with(alert: alert).critical_notification }

    it "sends to the organization billing email" do
      expect(mail.to).to eq(["ops@forest.ua"])
    end

    it "includes alert type and cluster name in the subject" do
      expect(mail.subject).to include(alert.alert_type.humanize)
      expect(mail.subject).to include(cluster.name)
    end

    it "includes the S-NET prefix in the subject" do
      expect(mail.subject).to include("[S-NET]")
    end

    it "renders the body" do
      expect(mail.body.encoded).to be_present
    end
  end
end
