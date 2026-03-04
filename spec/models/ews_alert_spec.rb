# frozen_string_literal: true

require "rails_helper"

RSpec.describe EwsAlert, type: :model do
  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:close_associated_maintenance!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
  end

  describe "#resolve!" do
    it "sets status and resolved_at" do
      alert = create(:ews_alert, :drought)
      user = create(:user, :forester)

      alert.resolve!(user: user, notes: "Irrigation activated manually")
      alert.reload

      expect(alert).to be_status_resolved
      expect(alert.resolved_at).not_to be_nil
      expect(alert.resolver).to eq(user)
      expect(alert.resolution_notes).to eq("Irrigation activated manually")
    end
  end

  describe "#coordinates" do
    it "returns tree coordinates when tree is present" do
      alert = create(:ews_alert, :drought)
      coords = alert.coordinates

      expect(coords).to eq([ alert.tree.latitude, alert.tree.longitude ])
    end
  end

  describe "#actionable?" do
    it "returns true for critical fire" do
      alert = create(:ews_alert, :fire)
      expect(alert).to be_actionable
    end

    it "returns false for medium drought" do
      alert = create(:ews_alert, :drought)
      expect(alert).not_to be_actionable
    end
  end
end
