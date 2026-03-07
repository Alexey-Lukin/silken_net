# frozen_string_literal: true

require "rails_helper"

RSpec.describe SingleNotificationWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:alert) { create(:ews_alert, :fire, cluster: cluster) }

  describe "#perform" do
    context "with SMS channel" do
      it "logs SMS delivery for user with phone number" do
        user = create(:user, :forester, organization: organization, phone_number: "+380501234567")

        expect(Rails.logger).to receive(:info).with(/SMS.*#{user.full_name}/)

        described_class.new.perform(user.id, alert.id, "sms")
      end

      it "skips SMS when user has no phone number" do
        user = create(:user, :forester, organization: organization, phone_number: nil)

        expect(Rails.logger).not_to receive(:info).with(/SMS/)

        described_class.new.perform(user.id, alert.id, "sms")
      end
    end

    context "with push channel" do
      it "logs push notification delivery" do
        user = create(:user, :admin, organization: organization)

        expect(Rails.logger).to receive(:info).with(/Push.*#{user.email_address}/)

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
  end
end
