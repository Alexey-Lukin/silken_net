# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Maintenance and ecosystem healing flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }
  let(:admin) { create(:user, :admin, organization: organization) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "MaintenanceRecord triggers EcosystemHealingWorker" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "enqueues EcosystemHealingWorker on creation" do
      record = create(:maintenance_record, user: admin, maintainable: tree)
      expect(EcosystemHealingWorker.jobs.size).to eq(1)
      expect(EcosystemHealingWorker.jobs.first["args"]).to eq([ record.id ])
    end

    it "marks tree as removed on decommissioning" do
      record = create(:maintenance_record, user: admin, maintainable: tree,
                                           action_type: :decommissioning)
      EcosystemHealingWorker.new.perform(record.id)

      expect(tree.reload.status).to eq("removed")
    end

    it "resolves associated EWS alert" do
      alert = create(:ews_alert, cluster: cluster, tree: tree, status: :active)
      record = create(:maintenance_record, user: admin, maintainable: tree,
                                           ews_alert: alert)
      EcosystemHealingWorker.new.perform(record.id)

      alert.reload
      expect(alert.status).to eq("resolved")
      expect(alert.resolved_at).to be_present
    end
  end

  describe "EWS alert resolution clears silence filter" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "clears cache silence key on alert resolution" do
      # Create a fire alert with silence filter
      log = create(:telemetry_log, tree: tree, temperature_c: 70,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 25.0)
      AlertDispatchService.analyze_and_trigger!(log)

      alert = EwsAlert.last
      silence_key = "ews_silence:#{tree.id}:fire_detected"
      expect(Rails.cache.exist?(silence_key)).to be true

      # Resolve the alert
      alert.resolve!(user: admin, notes: "Fire extinguished")
      expect(Rails.cache.exist?(silence_key)).to be false

      # Now a new fire alert can be created
      log2 = create(:telemetry_log, tree: tree, temperature_c: 72,
                                    bio_status: :homeostasis, voltage_mv: 3500,
                                    acoustic_events: 5, z_value: 25.0)
      expect { AlertDispatchService.analyze_and_trigger!(log2) }
        .to change(EwsAlert, :count).by(1)
    end
  end

  describe "MaintenanceRecord validations" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "requires photos for repair actions" do
      record = build(:maintenance_record, :repair, user: admin, maintainable: tree)
      expect(record).not_to be_valid
      expect(record.errors[:photos]).to be_present
    end

    it "requires photos for installation actions" do
      record = build(:maintenance_record, :installation, user: admin, maintainable: tree)
      expect(record).not_to be_valid
      expect(record.errors[:photos]).to be_present
    end

    it "does not require photos for inspection actions" do
      record = build(:maintenance_record, user: admin, maintainable: tree,
                                          action_type: :inspection)
      expect(record).to be_valid
    end

    it "calculates total cost correctly" do
      record = build(:maintenance_record, :with_cost, user: admin, maintainable: tree)
      # labor_hours: 2.5 * $50/hr = $125 + parts_cost: $150 = $275
      expect(record.total_cost).to eq(275.0)
    end

    it "validates performed_at is not in the future" do
      record = build(:maintenance_record, user: admin, maintainable: tree,
                                          performed_at: 1.day.from_now)
      expect(record).not_to be_valid
      expect(record.errors[:performed_at]).to be_present
    end
  end

  describe "Actuator repair via EcosystemHealingWorker" do
    let!(:gateway) { create(:gateway, :online, cluster: cluster) }
    let!(:actuator) { create(:actuator, gateway: gateway, state: :maintenance_needed) }

    it "resets actuator to idle on repair record" do
      record = create(:maintenance_record, :repair, user: admin,
                                           maintainable: actuator,
                                           photos: [
                                             fixture_file_upload("spec/fixtures/files/test_photo.jpg", "image/jpeg")
                                           ])
      EcosystemHealingWorker.new.perform(record.id)

      expect(actuator.reload.state).to eq("idle")
    end
  end
end
